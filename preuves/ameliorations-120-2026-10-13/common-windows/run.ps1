$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 required'}
foreach($f in (Get-Content ($root+'\transfer.json') -Raw|ConvertFrom-Json)){if((Get-FileHash ($root+'\'+$f.Path)).Hash -ine $f.SHA256){throw ('Transferred bytes changed: '+$f.Path)}}
$m=Get-Content ($root+'\manifest.json') -Raw|ConvertFrom-Json
foreach($f in $m.Files){[void][Reflection.Assembly]::LoadFrom(($root+'\'+$f.Name))}
$rows=@()
foreach($f in $m.Files|Where-Object {$_.Name -like 'M4D.Admin.Common.Tests.*.dll'}){
 $a=[Reflection.Assembly]::LoadFrom(($root+'\'+$f.Name))
 $methods=@($a.GetExportedTypes()|ForEach-Object {$_.GetMethod('Run',[Reflection.BindingFlags]'Public,Static')}|Where-Object {$_ -and $_.GetParameters().Count -eq 0})
 if($methods.Count -ne 1){throw 'Ambiguous entry point'}
 $count=$methods[0].Invoke($null,$null)
 $rows+=@{Name=$f.Name;Assertions=$count;SHA256=$f.SHA256}
}
& ($root+'\Run-WpfContracts.ps1') -BundleDirectory $root -ReportPath ($root+'\wpf.json')
[ordered]@{Status='PASS';SourceCommit='a050525abb46696d6b1516b18cccc2b837908a09';PS=$PSVersionTable.PSVersion.ToString();CLR=[Environment]::Version.ToString();Windows=[Environment]::OSVersion.ToString();Computer=$env:COMPUTERNAME;Scope='Isolated Common contracts on Windows; no Pesto GUI or AD operation';Results=$rows;Wpf=(Get-Content ($root+'\wpf.json') -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 8|Set-Content ($root+'\report.json') -Encoding UTF8

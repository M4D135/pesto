#requires -Version 5.1
[CmdletBinding()]
param(
 [ValidateRange(1,500)][int]$Cycles=32,
 [ValidateRange(1,50)][int]$WarmupCycles=4,
 [ValidateRange(1,100)][int]$SampleEvery=8,
 [ValidateRange(1,900)][int]$MaxDurationSeconds=120,
 [ValidateRange(0,600)][int]$MinimumDurationSeconds=0,
 [ValidateRange(1,5000)][int]$MaxCycles=1000,
 [string]$ReportPath=''
)
$ErrorActionPreference='Stop'
if($MaxCycles -lt $Cycles){throw 'MaxCycles doit être supérieur ou égal à Cycles.'}
if($MinimumDurationSeconds -ge $MaxDurationSeconds){throw 'MinimumDurationSeconds doit être inférieur à MaxDurationSeconds (échauffement inclus dans le maximum).'}
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis (WPF).'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Lancer avec powershell.exe -STA.'}
if($ReportPath){$ReportPath=[IO.Path]::GetFullPath($ReportPath);if(Test-Path -LiteralPath $ReportPath){throw 'Rapport existant.'}}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$source=Join-Path $PSScriptRoot 'PestoWpfSessionProbe.cs'
$shell=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Shell.xaml'
if(-not ('PestoWpfSessionProbe' -as [type])){
 Add-Type -Path $source -ReferencedAssemblies @([Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location,[System.Xaml.XamlReader].Assembly.Location,'System.dll')
}
$measurement=[PestoWpfSessionProbe]::Run([IO.File]::ReadAllText($shell),$Cycles,$WarmupCycles,$SampleEvery,$MaxDurationSeconds,$MinimumDurationSeconds,$MaxCycles)
$report=[pscustomobject][ordered]@{
 Schema=1;Verdict='MEASURED_ONLY';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString()
 ToolSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
 OperatingSystem=[Environment]::OSVersion.VersionString;Culture=[Globalization.CultureInfo]::CurrentCulture.Name;UICulture=[Globalization.CultureInfo]::CurrentUICulture.Name;ClrVersion=[Environment]::Version.ToString();Architecture=$env:PROCESSOR_ARCHITECTURE
 ShellSha256=(Get-FileHash -LiteralPath $shell -Algorithm SHA256).Hash;ProbeSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
 Measurement=$measurement;PagesPerCycle=8;DurationBoundSeconds=$MaxDurationSeconds
 Scope='Isolated real shell XAML: create/show off-screen, select every page, close, dispatcher drain and GC between samples. No engine, business handlers, AD or Pesto process. No Narrator or physical DPI validation. Weak references track Windows only; metrics do not prove absence of application leaks or event-subscription retention. Duration limit checked between cycles, not a preemptive timeout.'
}
if($ReportPath){
 $temporary=Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) ('.pesto-wpf-session-'+[Guid]::NewGuid().ToString('N')+'.tmp')
 try{
  $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 7));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  [IO.File]::Move($temporary,$ReportPath)
 }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
$report

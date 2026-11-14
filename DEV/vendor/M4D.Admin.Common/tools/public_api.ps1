#requires -Version 7.4
param([Parameter(Mandatory)][string]$BundleDirectory,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$surface=[ordered]@{}
foreach($path in Get-ChildItem -LiteralPath $BundleDirectory -Filter 'M4D.Admin.Common.*.dll' -File|Where-Object{$_.Name -notmatch '\.Tests\.|\.Wpf\.dll$'}|Sort-Object Name){
 $assembly=[Reflection.Assembly]::LoadFrom($path.FullName)
 $rows=@(foreach($type in $assembly.GetExportedTypes()|Sort-Object FullName){
  'type '+$type.FullName
  foreach($member in $type.GetMembers([Reflection.BindingFlags]'DeclaredOnly,Public,Instance,Static')|Sort-Object Name){$type.FullName+'::'+$member.MemberType+' '+$member.ToString()}
 })
 $surface[$path.Name]=@($rows|Sort-Object -Unique)
}
$surface|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

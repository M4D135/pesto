# Test the exact constant function from the C# source, never a separately maintained copy.
param([Parameter(Mandatory=$true)][string]$SourcePath)
$ErrorActionPreference='Stop'
$file=Get-Item -LiteralPath $SourcePath -ErrorAction Stop
if($file.Length -le 0 -or $file.Length -gt 1048576){throw 'Source absente ou trop volumineuse.'}
$source=[IO.File]::ReadAllText($file.FullName)
$pattern='(?ms)^function Get-NativeCode\(\$e\)\{\r?\n.*?^\}\r?\n(?=function Out-PestoResult)'
$regex=[Text.RegularExpressions.Regex]::new($pattern,[Text.RegularExpressions.RegexOptions]::None,[TimeSpan]::FromSeconds(1))
$matches=$regex.Matches($source)
if($matches.Count -ne 1){throw 'Fonction native unique non trouvée dans le script constant.'}
$function=$matches[0].Value
. ([scriptblock]::Create($function))
$cases=@(
  @{Value=[ComponentModel.Win32Exception]::new(5);Expected=5},
  @{Value=[ComponentModel.Win32Exception]::new(1314);Expected=1314},
  @{Value=[Runtime.InteropServices.COMException]::new('fixture',-2147024891);Expected=5},
  @{Value=[Exception]::new('outer',[ComponentModel.Win32Exception]::new(1314));Expected=1314},
  @{Value=[InvalidOperationException]::new('fixture');Expected=$null},
  @{Value=[Runtime.InteropServices.COMException]::new('fixture',-2147467259);Expected=$null}
)
foreach($case in $cases){$actual=Get-NativeCode $case.Value;if($actual -ne $case.Expected){throw ('Native code mismatch: '+$actual)}}
$sha=[Security.Cryptography.SHA256]::Create()
try{
  $sourceHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()
  $functionHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($function)))).Replace('-','').ToLowerInvariant()
}finally{$sha.Dispose()}
@{ok=$true;cases=$cases.Count;sourceSha256=$sourceHash;functionSha256=$functionHash}|ConvertTo-Json -Compress

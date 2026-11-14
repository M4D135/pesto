namespace Pesto.Engine.Live;

/// <summary>Fixed PS 5.1 workers. Only Observe imports AD; Apply calls the fixed local djoin executable once.</summary>
public static class WindowsOfflineJoinScripts
{
    private static readonly string Common = BootIdentityScript.Source + """
$ErrorActionPreference='Stop'
function Get-PestoOfflineLocal{
  $r=[ordered]@{computer=$null;activeName=$null;configuredName=$null;machineId=$null;domain=$null;partOfDomain=$null;domainRole=$null;bootUtc=$null;administrator=$null;error=$null}
  try{
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop
    $r.computer=[string]$cs.Name
    $r.activeName=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $r.configuredName=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $r.machineId=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $r.domain=[string]$cs.Domain;$r.partOfDomain=[bool]$cs.PartOfDomain;$r.domainRole=[int]$cs.DomainRole
    $r.bootUtc=Get-PestoStableBootUtc
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{$r.administrator=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
  }catch{$r.error='Local Windows evidence is incomplete.'}
  return [pscustomobject]$r
}
function Assert-PestoOfflinePath([string]$path){
  if(-not [IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\') -or $path -match '["\r\n]'){throw 'Local path required.'}
  $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($path));if($drive.DriveType -eq [IO.DriveType]::Network){throw 'Network path refused.'}
  $full=[IO.Path]::GetFullPath($path);$root=[IO.Path]::GetPathRoot($full);$current=$root
  foreach($part in $full.Substring($root.Length).Split([char[]]@('\','/'),[StringSplitOptions]::RemoveEmptyEntries)){
    $current=[IO.Path]::Combine($current,$part)
    try{$attributes=[IO.File]::GetAttributes($current)}catch [IO.FileNotFoundException]{break}catch [IO.DirectoryNotFoundException]{break}
    if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Linked path refused.'}
  }
}
function Get-PestoOfflineHash([string]$path,[int]$maximum){
  Assert-PestoOfflinePath $path
  $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{
    if($stream.Length -lt 1 -or $stream.Length -gt $maximum){throw 'File size refused.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  }finally{$stream.Dispose()}
}
function Write-PestoOfflineNew([string]$path,$value){
  Assert-PestoOfflinePath $path
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Depth 12 -Compress))
  $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

""";

    public static string ReadLocal => Common + """
Get-PestoOfflineLocal|ConvertTo-Json -Depth 4 -Compress
""";

    public static string Apply => Common + """
$process=$null;$plainPin=$null;$started=$false;$code=$null;$mayRun=$false;$marker=$false;$j=$null
try{
  $text=[Console]::In.ReadToEnd();if($text.Length -gt 65536){throw 'Payload too large.'};$j=$text|ConvertFrom-Json
  $b=$j.Command.Binding;$baseline=$j.Command.Baseline
  if($env:PESTO_READONLY_SESSION -eq '1' -or $b.Id -cnotmatch '^[a-f0-9]{64}$' -or $j.Command.ReceiptId -cnotmatch '^receipt-[a-f0-9]{32}$'){throw 'Admission refused.'}
  Assert-PestoOfflinePath ([string]$j.ConfigurationPath);Assert-PestoOfflinePath ([string]$j.IntentPath)
  Assert-PestoOfflinePath ([string]$j.ReceiptPath);Assert-PestoOfflinePath ([string]$j.PlainPath)
  Assert-PestoOfflinePath ([string]$j.AttemptPath);Assert-PestoOfflinePath ([string]$j.ResultPath)
  if((Get-PestoOfflineHash $j.ConfigurationPath 1048576) -cne $b.ConfigurationSha256 -or (Get-PestoOfflineHash $j.IntentPath 65536) -cne $j.Command.IntentSha256){throw 'Confirmed evidence changed.'}
  $intent=[IO.File]::ReadAllText($j.IntentPath)|ConvertFrom-Json
  if($intent.State -cne 'Requested' -or $intent.WorkerMayRun -ne $true -or $intent.Binding.Id -cne $b.Id -or $intent.ReceiptId -cne $j.Command.ReceiptId -or $intent.PlanId -cne $j.Command.PlanId){throw 'Durable intent absent.'}
  if((Get-PestoOfflineHash $j.ReceiptPath 65536) -cne $intent.SourceReceiptSha256){throw 'Durable receipt changed.'}
  $receipt=[IO.File]::ReadAllText($j.ReceiptPath)|ConvertFrom-Json
  if($receipt.Kind -cne 'offlineJoin' -or $receipt.OfflineJoin -cne 'Requested' -or $receipt.Phase -cne 'Running' -or $receipt.ReceiptId -cne $j.Command.ReceiptId -or $receipt.OfflineJoinId -cne $b.Id){throw 'Durable receipt absent.'}
  $cfg=[IO.File]::ReadAllText($j.ConfigurationPath)|ConvertFrom-Json
  if($cfg.POLICY.AllowOfflineJoin -isnot [bool] -or -not $cfg.POLICY.AllowOfflineJoin -or $cfg.POLICY.IncidentMode -eq $true -or $cfg.POLICY.CoordinationRoot -or $cfg.POLICY.CoordinationRequired -eq $true -or @($cfg.POLICY.ExcludedGroupGuids|Where-Object{$_}).Count -gt 0){throw 'Offline policy refused.'}
  foreach($name in @('Simulation','GUI','HorsDomaine','MauvaiseOU','ForceADM','BPVerifNomAD')){
    if($cfg.DEBUG -and ($cfg.DEBUG.$name -eq $true -or [string]$cfg.DEBUG.$name -ieq 'true')){throw 'Debug policy refused.'}
  }
  $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\M4D\Pesto',$false)
  try{
    $incident=$false;$scenario=$null
    if($key){
      $names=$key.GetValueNames()
      if($names -ccontains 'IncidentMode'){
        if($key.GetValueKind('IncidentMode') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or $key.GetValue('IncidentMode') -notin @(0,1)){throw 'Managed policy unreadable.'}
        $incident=($key.GetValue('IncidentMode') -eq 1)
      }
      if($names -ccontains 'ScenarioJson'){
        if($key.GetValueKind('ScenarioJson') -ne [Microsoft.Win32.RegistryValueKind]::String){throw 'Managed scenario unreadable.'}
        $scenario=[string]$key.GetValue('ScenarioJson',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
      }
    }
    if($incident -or $scenario -cne $j.ManagedPolicy.ScenarioJson){throw 'Managed policy changed.'}
  }finally{if($key){$key.Dispose()}}
  $local=Get-PestoOfflineLocal
  if($local.error -or $local.administrator -ne $true -or $local.partOfDomain -ne $false -or $local.domainRole -notin @(0,2) -or $local.computer -ine $b.Computer -or $local.activeName -ine $b.Computer -or $local.configuredName -ine $b.Computer -or $local.machineId -ine $b.MachineId -or $local.domain -ine $baseline.Domain -or $local.domainRole -ne $baseline.DomainRole -or [DateTimeOffset]::Parse($local.bootUtc) -ne [DateTimeOffset]::Parse($baseline.BootUtc)){throw 'Local identity changed.'}
  if([DateTimeOffset]::Parse($j.Command.PlanExpiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($b.ExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Confirmed plan expired.'}
  if((Get-PestoOfflineHash $j.PlainPath 1048576) -cne $b.Id){throw 'Blob changed.'}
  $plainPin=[IO.File]::Open($j.PlainPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $windows=[Environment]::GetFolderPath('Windows');$native=Join-Path $windows 'System32\djoin.exe'
  Assert-PestoOfflinePath $windows;Assert-PestoOfflinePath $native
  if(-not [IO.File]::Exists($native)){throw 'Native tool unavailable.'}
  # This exclusive marker is flushed before the only native call, even if the parent loses its reply.
  Write-PestoOfflineNew $j.AttemptPath ([ordered]@{Schema=1;Id=$b.Id;ReceiptId=$j.Command.ReceiptId;IntentSha256=$j.Command.IntentSha256;ConfigurationSha256=$b.ConfigurationSha256;MachineId=$b.MachineId;Utc=[DateTimeOffset]::UtcNow.ToString('o')})
  $marker=$true
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$native
  $info.Arguments='/requestodj /loadfile "'+$j.PlainPath+'" /windowspath "'+$windows+'" /localos'
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $process=[Diagnostics.Process]::new();$process.StartInfo=$info
  $mayRun=$true
  if(-not $process.Start()){throw 'Native start not confirmed.'};$started=$true
  # Neither output is materialized, logged, returned or parsed: native text can contain secret data.
  $out=$process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null);$err=$process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
  if(-not $process.WaitForExit(120000)){throw 'Native timeout.'}
  $code=[int]$process.ExitCode;$mayRun=$false
  $out.GetAwaiter().GetResult();$err.GetAwaiter().GetResult()
}catch{
  if($process){try{if($process.HasExited){$mayRun=$false}}catch{}}
}finally{
  if($plainPin){$plainPin.Dispose()}
  if($process){$process.Dispose()}
}
$result=[ordered]@{Schema=1;Id=$(if($j){$j.Command.Binding.Id}else{''});ReceiptId=$(if($j){$j.Command.ReceiptId}else{''});IntentSha256=$(if($j){$j.Command.IntentSha256}else{''});Started=$started;NativeCode=$code;WorkerMayRun=$mayRun;Utc=[DateTimeOffset]::UtcNow.ToString('o')}
if($marker){try{Write-PestoOfflineNew $j.ResultPath $result}catch{exit 97}}
$result|ConvertTo-Json -Depth 4 -Compress
""";

    public static string Observe => Common + """
$result=[ordered]@{local=$null;adGuid=$null;adName=$null;adOu=$null;adDomain=$null;domainController=$null;secureChannel=$null;observedUtc=[DateTimeOffset]::UtcNow.ToString('o');error=$null}
try{
  $text=[Console]::In.ReadToEnd();if($text.Length -gt 32768){throw 'Payload too large.'};$j=$text|ConvertFrom-Json;$b=$j.Binding
  $before=Get-PestoOfflineLocal;$result.local=$before
  if($before.error -or $before.partOfDomain -ne $true -or $before.domainRole -notin @(1,3) -or $before.domain -ine $b.Domain -or $before.computer -ine $b.Computer -or $before.activeName -ine $b.Computer -or $before.configuredName -ine $b.Computer -or $before.machineId -ine $b.MachineId -or [DateTimeOffset]::Parse($before.bootUtc) -le [DateTimeOffset]::Parse($j.AppliedBootUtc)){throw 'Postboot local proof absent.'}
  # This is the only worker permitted to import AD or contact a DC, after explicit Observe and local proof.
  Import-Module -Name ([string]$j.ModulePath) -ErrorAction Stop
  $controllers=@(Get-ADDomainController -Discover -Service ADWS -DomainName ([string]$b.Domain) -ForceDiscover -ErrorAction Stop)
  if($controllers.Count -ne 1 -or $controllers[0].Domain -ine $b.Domain -or -not $controllers[0].HostName){throw 'Domain controller not proved.'}
  $server=[string]$controllers[0].HostName
  $domain=Get-ADDomain -Server $server -ErrorAction Stop
  if($domain.DNSRoot -ine $b.Domain){throw 'Directory domain differs.'};$result.adDomain=[string]$domain.DNSRoot
  $pc=Get-ADComputer -Identity ([Guid]$b.ExpectedAdGuid) -Properties Name,ObjectGUID,DistinguishedName,userAccountControl -Server $server -ErrorAction Stop
  $result.adGuid=[string]$pc.ObjectGUID;$result.adName=[string]$pc.Name
  if($null -eq $pc.userAccountControl){throw 'Directory role unknown.'}
  $result.domainController=(([long]$pc.userAccountControl -band 8192) -ne 0)
  $dn=[string]$pc.DistinguishedName
  for($i=0;$i -lt $dn.Length;$i++){
    if($dn[$i] -eq '\'){$i++;continue}
    if($dn[$i] -eq ','){$result.adOu=$dn.Substring($i+1);break}
  }
  $result.secureChannel=[bool](Test-ComputerSecureChannel -Server $server -ErrorAction Stop)
  $after=Get-PestoOfflineLocal
  foreach($field in @('computer','activeName','configuredName','machineId','domain','partOfDomain','domainRole','bootUtc')){
    if($after.$field -ine $before.$field){throw 'Local identity changed during observation.'}
  }
  if($after.error){throw 'Final local proof absent.'};$result.local=$after
}catch{$result.error='ODJ observation incomplete; no replay or repair.'}
$result.observedUtc=[DateTimeOffset]::UtcNow.ToString('o')
$result|ConvertTo-Json -Depth 6 -Compress
""";
}

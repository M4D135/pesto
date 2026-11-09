using System.Text;
using System.Text.Json;

namespace Pesto.Engine;

public sealed partial class RemoteWindowsDiagnosticTask
{
    public static string Script(RemoteWindowsEvidenceRequest request, string nonce)
    {
        RemoteWindowsEvidenceProtocol.ValidateRequest(request);
        if (!RemoteWindowsEvidenceProtocol.IsNonce(nonce)) throw RemoteWindowsEvidenceProtocol.Invalid("Nonce invalide.");
        var encoded = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new { Request = request, Nonce = nonce,
            RequestSha256 = RemoteWindowsEvidenceProtocol.RequestHash(request, nonce) }));
        return BootIdentity.ScriptSource + "\n$binding=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded + "'))|ConvertFrom-Json\n" + Body;
    }

    public const string Body = """
$ErrorActionPreference='Stop'
$output=$null
try{
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  try{if($identity.User.Value -ne 'S-1-5-18'){exit 44}}finally{$identity.Dispose()}
  $r=$binding.Request
  $cs=@(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 10 -ErrorAction Stop)
  if($cs.Count -ne 1 -or -not $cs[0].PartOfDomain -or $cs[0].DomainRole -notin @(1,3) -or $cs[0].Domain -ine $r.Domain){exit 44}
  $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
  $machineGuid=[Guid]::Empty
  if(-not [Guid]::TryParse($machine,[ref]$machineGuid) -or $machineGuid -eq [Guid]::Empty -or ($r.ExpectedMachineId -and $machine -ine $r.ExpectedMachineId)){exit 44}
  if($env:COMPUTERNAME -ine $r.ExpectedActiveName -or $cs[0].Name -ine $r.ExpectedActiveName -or $active -ine $r.ExpectedActiveName -or $configured -ine $r.ExpectedConfiguredName){exit 44}
  $boot=Get-PestoStableBootUtc
  $channel=$null
  try{$checked=Test-ComputerSecureChannel -Server ([string]$r.Dc) -ErrorAction Stop;if($checked -is [bool]){$channel=[bool]$checked}}catch{}
  $value=[ordered]@{Schema=1;Nonce=[string]$binding.Nonce;RequestSha256=[string]$binding.RequestSha256;ReceiptId=[string]$r.ReceiptId;
    ExpectedAdGuid=[string]$r.ExpectedAdGuid;SystemSid='S-1-5-18';ActiveName=$active;ConfiguredName=$configured;Domain=[string]$cs[0].Domain;
    PartOfDomain=[bool]$cs[0].PartOfDomain;DomainRole=[int]$cs[0].DomainRole;MachineId=$machine;BootUtc=$boot;ObservedUtc=[DateTime]::UtcNow.ToString('o');SecureChannel=$channel}
  $json=$value|ConvertTo-Json -Depth 4 -Compress
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
  if($bytes.Length -gt 16384){exit 97}
  $folder=Join-Path $env:SystemRoot 'Temp'
  if(-not [IO.Directory]::Exists($folder)){exit 97}
  $parent=[IO.DirectoryInfo]::new($folder)
  while($parent){if(($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){exit 97};$parent=$parent.Parent}
  $path=Join-Path $folder ('PestoEvidence-'+[string]$binding.Nonce+'.json')
  $security=[Security.AccessControl.FileSecurity]::new()
  $security.SetAccessRuleProtection($true,$false)
  $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
  $security.SetOwner($system)
  foreach($sid in @($system,$admins)){$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))}
  # CREATE_NEW with the restrictive ACL: no existing file can be replaced, even before the first byte.
  $output=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[Security.AccessControl.FileSystemRights]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough,$security)
  $output.Write($bytes,0,$bytes.Length);$output.Flush($true);$output.Dispose();$output=$null
  exit 0
}catch{exit 97}finally{if($output){$output.Dispose()}}
""";
}

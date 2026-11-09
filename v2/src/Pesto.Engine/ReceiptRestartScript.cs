using System.Text;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>Closed action, bound to one MachineGuid and Kernel-General boot. No Force, credentials, repair or AD write.</summary>
public static class ReceiptRestartScript
{
    public static string LocalSource => BootIdentity.ScriptSource + "\n$j=[Console]::In.ReadToEnd()|ConvertFrom-Json\n" + Body;
    public static string RemoteSource(RestartCommand command)
    {
        ReceiptRestartRules.ValidateCommand(command);
        var encoded = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(command));
        return BootIdentity.ScriptSource + "\n$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded + "'))|ConvertFrom-Json\n" + Body;
    }

    private const string Body = """
$ErrorActionPreference='Stop'
$sent=$false
try{
  if(-not $j.LocalTarget -and [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18'){exit 96}
  $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
  $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
  $boot=[DateTimeOffset]::Parse((Get-PestoStableBootUtc),[Globalization.CultureInfo]::InvariantCulture)
  $expectedBoot=[DateTimeOffset]::Parse([string]$j.BootUtc,[Globalization.CultureInfo]::InvariantCulture)
  if($machine -ine [string]$j.MachineId -or $active -ine [string]$j.Computer -or $env:COMPUTERNAME -ine $active -or [string]$cs.Name -ine $active -or $configured -ine [string]$j.ConfiguredName -or $boot.UtcDateTime.Ticks -ne $expectedBoot.UtcDateTime.Ticks){exit 96}
  $joined=([bool]$cs.PartOfDomain -and [string]$cs.Domain -ieq [string]$j.Domain -and [int]$cs.DomainRole -in @(1,3))
  $pending=([bool]$j.LocalTarget -and [bool]$j.AllowPendingJoin -and [string]$j.OperationKind -eq 'join' -and -not $cs.PartOfDomain -and [string]$cs.Domain -ieq [string]$j.InitialWindowsDomain -and [int]$j.InitialDomainRole -in @(0,2) -and [int]$cs.DomainRole -eq [int]$j.InitialDomainRole)
  if(-not ($joined -or $pending)){exit 96}
  # A second invocation on another boot fails above. No task or shell argument can broaden this action.
  $sent=$true
  Restart-Computer -ErrorAction Stop
  exit 0
}catch{if($sent){exit 97}else{exit 96}}
""";
}

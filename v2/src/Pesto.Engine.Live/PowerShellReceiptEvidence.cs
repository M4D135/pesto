using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Pesto.Engine.Live;

internal sealed record NativeReceiptSnapshot(
    DateTimeOffset? BootUtc, string? MachineId, string? ActiveName, string? ConfiguredName, string? Domain,
    bool? PartOfDomain, bool? SecureChannel, string? AdGuid, string? AdName, string? AdOu, bool? AdProtected, string? Error, bool? DomainController = null, int? DomainRole = null)
{
    public RemoteWindowsProof? RemoteProof { get; init; }
}

/// <summary>Read-only Windows/AD evidence. This script contains no mutation, task, repair or reboot command.</summary>
internal static class PowerShellReceiptEvidence
{
    public static NativeReceiptSnapshot Read(string domain, string? dc, string? guid, bool local,
        string modulePath, ProtectedWindowsCredential? credential, string? remoteComputer = null)
    {
        if (!OperatingSystem.IsWindows()) return Unknown("La vérification Windows n’est pas disponible sur ce système.");
        try
        {
            var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
            {
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                UseShellExecute = false, CreateNoWindow = true, StandardInputEncoding = new UTF8Encoding(false),
                StandardOutputEncoding = new UTF8Encoding(false)
            };
            foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(Script)) })
                start.ArgumentList.Add(argument);
            using var process = Process.Start(start);
            if (process is null) return Unknown("La lecture Windows n’a pas démarré.");
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            process.StandardInput.Write(JsonSerializer.Serialize(new { Domain = domain, Server = dc ?? domain,
                Guid = guid, Local = local, ModulePath = modulePath, Credential = credential, RemoteComputer = remoteComputer }));
            process.StandardInput.Close();
            if (!process.WaitForExit(30000))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return Unknown("La lecture Windows/AD a expiré : aucune conclusion de réussite.");
            }
            var json = output.GetAwaiter().GetResult();
            _ = errors.GetAwaiter().GetResult();
            if (json.Length > 65536) return Unknown("Réponse de vérification trop volumineuse.");
            using var document = JsonDocument.Parse(json);
            var r = document.RootElement;
            return new NativeReceiptSnapshot(Date(r, "bootUtc"), Text(r, "machineId"), Text(r, "activeName"),
                Text(r, "configuredName"), Text(r, "domain"), Flag(r, "partOfDomain"), Flag(r, "secureChannel"),
                Text(r, "adGuid"), Text(r, "adName"), Text(r, "adOu"), Flag(r, "adProtected"), Text(r, "error"), Flag(r, "domainController"), Number(r, "domainRole"));
        }
        catch (Exception) { return Unknown("La lecture Windows/AD n’a pas fourni de preuve exploitable."); }
    }

    private static NativeReceiptSnapshot Unknown(string reason) => new(null, null, null, null, null, null, null, null, null, null, null, reason);
    private static string? Text(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static bool? Flag(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False ? v.GetBoolean() : null;
    private static int? Number(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var number) ? number : null;
    private static DateTimeOffset? Date(JsonElement r, string key) => DateTimeOffset.TryParse(Text(r, key), System.Globalization.CultureInfo.InvariantCulture,
        System.Globalization.DateTimeStyles.None, out var value) ? value : null;

    public static string ConstantScript => Script;
    private static readonly string Script = BootIdentityScript.Source + """
$ErrorActionPreference='Stop'
$secure=$null
$cim=$null
$r=@{bootUtc=$null;machineId=$null;activeName=$null;configuredName=$null;domain=$null;partOfDomain=$null;secureChannel=$null;adGuid=$null;adName=$null;adOu=$null;adProtected=$null;domainController=$null;domainRole=$null;error=$null}
try{
  $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
  if(-not $j.ModulePath){throw 'Module absent.'}
  Import-Module -Name ([string]$j.ModulePath) -ErrorAction Stop
  $adp=@{Server=[string]$j.Server}
  $channel=@{Server=[string]$j.Server;ErrorAction='Stop'}
  if($j.Credential){
    $bytes=$null
    try{
      Add-Type -AssemblyName System.Security
      $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.Credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
      $secure=New-Object Security.SecureString
      for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
      $secure.MakeReadOnly()
      $adp.Credential=New-Object Management.Automation.PSCredential([string]$j.Credential.userName,$secure)
      $channel.Credential=$adp.Credential
    }finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
  }
  if($j.Local){
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $r.bootUtc=Get-PestoStableBootUtc
    $r.machineId=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $r.activeName=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $r.configuredName=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $r.domain=[string]$cs.Domain
    $r.partOfDomain=[bool]$cs.PartOfDomain
    $r.domainRole=[int]$cs.DomainRole
    if($r.domainRole -ge 4){$r.domainController=$true}
    if($r.partOfDomain){try{$r.secureChannel=[bool](Test-ComputerSecureChannel @channel)}catch{$r.secureChannel=$null}}
  }
  if(-not $j.Local -and $j.RemoteComputer){
    if(-not $adp.Credential){throw 'Un compte AD explicite est nécessaire pour confirmer la cible distante.'}
    $options=New-CimSessionOption -Protocol Dcom
    $cim=New-CimSession -ComputerName ([string]$j.RemoteComputer) -Credential $adp.Credential -SessionOption $options -ErrorAction Stop
    $cs=Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $cim -ErrorAction Stop
    $r.activeName=[string]$cs.Name
    $r.domain=[string]$cs.Domain
    $r.partOfDomain=[bool]$cs.PartOfDomain
    $r.domainRole=[int]$cs.DomainRole
    if($r.domainRole -ge 4){$r.domainController=$true}
    # Optional complementary registry reads, as in V1: the authoritative WMI identity above is mandatory.
    try{
      $configured=Invoke-CimMethod -ClassName StdRegProv -Namespace root/default -CimSession $cim -MethodName GetStringValue -Arguments @{hDefKey=[uint32]2147483650;sSubKeyName='SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName';sValueName='ComputerName'} -ErrorAction Stop
      if($configured.ReturnValue -eq 0){$r.configuredName=[string]$configured.sValue}
      $identity=Invoke-CimMethod -ClassName StdRegProv -Namespace root/default -CimSession $cim -MethodName GetStringValue -Arguments @{hDefKey=[uint32]2147483650;sSubKeyName='SOFTWARE\Microsoft\Cryptography';sValueName='MachineGuid'} -ErrorAction Stop
      if($identity.ReturnValue -eq 0){$r.machineId=[string]$identity.sValue}
    }catch{}
  }
  if($j.Guid){
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$j.Guid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID absent.'}
    $pc=Get-ADComputer -Identity $id -Properties Name,ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl -ErrorAction Stop @adp
    if($null -ne $pc.userAccountControl -and $r.domainController -ne $true){$r.domainController=(([long]$pc.userAccountControl -band 8192) -ne 0)}
    $r.adGuid=[string]$pc.ObjectGUID
    $r.adName=[string]$pc.Name
    $r.adProtected=if($pc.ProtectedFromAccidentalDeletion -is [bool]){[bool]$pc.ProtectedFromAccidentalDeletion}else{$null}
    $dn=[string]$pc.DistinguishedName
    for($i=0;$i -lt $dn.Length;$i++){
      if($dn[$i] -eq '\'){$i++;continue}
      if($dn[$i] -eq ','){$r.adOu=$dn.Substring($i+1);break}
    }
  }
}catch{$r.error='Lecture Windows/AD incomplète : aucune conclusion de réussite.'}
finally{if($cim){Remove-CimSession -CimSession $cim -ErrorAction SilentlyContinue};if($secure){$secure.Dispose()}}
$r|ConvertTo-Json -Depth 4 -Compress
""";
}

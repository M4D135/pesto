using System.Text;
using System.Text.Json;
using Pesto.Engine;

namespace Pesto.Engine.Live;

/// <summary>Fixed PS5.1 worker. A unique target journal is flushed before one /leave; inspection has no mutation branch.</summary>
public static class PowerShellEntraWorker
{
    public static string Build(EntraLeaveCommand command, bool inspect = false)
    {
        EntraLeaveEvidence.Validate(command);
        // Keep the fixed encoded command below Windows' command-line limit even for a 2 KiB OU DN.
        // The complete request remains in the local journal; only facts used by this worker cross to the target.
        var json = Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(new
        {
            command.ReceiptId, command.Nonce, command.MachineId,
            Request = new { command.Request.Kind, command.Request.Computer, command.Request.ComputerGuid,
                command.Request.Domain, command.Request.ConfigurationSha256 }
        }));
        return "$j=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + json + "'))|ConvertFrom-Json\r\n"
            + "$inspection=" + (inspect ? "$true" : "$false") + "\r\n" + Script;
    }

    public const string Script = """
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$leavePending=$false;$leaveDone=$false;$targetDir=$null;$sequence=0;$guard=$null;$owned=$false;$native=$null
$effect='NotRequested';$mayRun=$false;$resultCode=44;$message='Retrait non lancé.'
function Assert-EntraPath([string]$path){
  $p=[IO.Path]::GetFullPath($path)
  while($p){
    if([IO.File]::Exists($p)-or [IO.Directory]::Exists($p)){
      if(([IO.File]::GetAttributes($p)-band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'Stockage lié refusé.'}
    }
    $next=[IO.Path]::GetDirectoryName($p);if($next -eq $p){break};$p=$next
  }
}
function Get-EntraState([string]$text,[int]$code){
  if($code -ne 0 -or $text.Length -gt 65536){return 'unknown'}
  $a=[regex]::Matches($text,'(?im)^[ \t]*AzureAdJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$')
  $d=[regex]::Matches($text,'(?im)^[ \t]*DomainJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$')
  if($a.Count -ne 1 -or $d.Count -ne 1 -or $d[0].Groups[1].Value -ine 'YES'){return 'unknown'}
  if($a[0].Groups[1].Value -ieq 'YES'){return 'hybrid'};return 'adOnly'
}
function Save-EntraTarget([string]$phase,[string]$state,[bool]$couldRun){
  if(-not $targetDir){throw 'Stockage de preuve absent.'}
  Assert-EntraPath $targetDir
  $script:sequence++
  $entry=[ordered]@{Schema=1;ReceiptId=[string]$j.ReceiptId;Nonce=[string]$j.Nonce;Computer=[string]$env:COMPUTERNAME;
    MachineId=$machineId;Domain=[string]$j.Request.Domain;ComputerGuid=[string]$j.Request.ComputerGuid;
    ConfigurationSha256=[string]$j.Request.ConfigurationSha256;Phase=$phase;Effect=$state;MayStillRun=$couldRun;
    Utc=[DateTimeOffset]::UtcNow.ToString('o');WorkerPid=$PID;NativePid=$(if($native){$native.Id}else{$null})}
  $path=Join-Path $targetDir ($script:sequence.ToString('D4')+'.json')
  $bytes=[Text.Encoding]::UTF8.GetBytes(($entry|ConvertTo-Json -Depth 4 -Compress))
  $f=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
  try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Read-Dsreg([int]$timeout){
  $p=$null
  try{
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe;$start.Arguments='/status'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $p=[Diagnostics.Process]::new();$p.StartInfo=$start
    if(-not $p.Start()){throw 'Lecture dsregcmd non démarrée.'}
    $out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit($timeout*1000)){try{$p.Kill()}catch{};throw 'Lecture dsregcmd expirée.'}
    $text=$out.GetAwaiter().GetResult();$null=$err.GetAwaiter().GetResult()
    return Get-EntraState $text $p.ExitCode
  }finally{if($p){$p.Dispose()}}
}
try{
  if([string]$j.ReceiptId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' -or [string]$j.Nonce -notmatch '^[a-f0-9]{64}$' -or
      [string]$j.Request.Kind -cnotin @('rename','renameMove')){throw 'Demande cible invalide.'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  try{$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
  if(-not $admin){throw 'Préparation non élevée.'}
  $machineId=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
  if(-not $machineId -or $machineId -ine [string]$j.MachineId){throw 'Identité Windows différente.'}
  $cs=@(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop)
  if($cs.Count -ne 1 -or -not $cs[0].PartOfDomain -or $cs[0].DomainRole -notin @(1,3) -or
      [string]$cs[0].Domain -ine [string]$j.Request.Domain){throw 'Domaine ou rôle Windows non conforme.'}
  $dir=if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){'Sysnative'}else{'System32'}
  $exe=Join-Path ([Environment]::GetFolderPath('Windows')) ($dir+'\dsregcmd.exe')
  if(-not [IO.File]::Exists($exe)){throw 'dsregcmd absent.'}
  $targetDir=[IO.Path]::Combine([Environment]::GetFolderPath('CommonApplicationData'),'GP','V2','entra-target',[string]$j.ReceiptId)
  Assert-EntraPath $targetDir
  $guard=[Threading.Mutex]::new($false,('Global\GP_Entra_'+[string]$j.ReceiptId))
  try{$owned=$guard.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(-not $owned){$mayRun=$true;throw 'Le travailleur Entra peut encore agir.'}
  if($inspection){
    # Read-only inspection. No directory, task, receipt, /leave, repair or reboot is created here.
    $files=@(Get-ChildItem -LiteralPath $targetDir -File -ErrorAction Stop|Sort-Object Name)
    if($files.Count -lt 1 -or $files.Count -gt 16){throw 'Preuve cible absente ou invalide.'}
    $last=$null;$n=0
    foreach($file in $files){
      $n++;if($file.Name -cne ($n.ToString('D4')+'.json') -or $file.Length -gt 65536){throw 'Séquence cible invalide.'}
      Assert-EntraPath $file.FullName
      $v=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)|ConvertFrom-Json
      if($v.Schema -ne 1 -or $v.ReceiptId -cne $j.ReceiptId -or $v.Nonce -cne $j.Nonce -or
          $v.MachineId -ine $machineId -or $v.Domain -ine $j.Request.Domain -or
          $v.ComputerGuid -ine $j.Request.ComputerGuid -or $v.ConfigurationSha256 -ine $j.Request.ConfigurationSha256){throw 'Preuve cible différente.'}
      $last=$v
    }
    # An abandoned controller or completed task alone does not prove its native child stopped.
    if(@(Get-CimInstance -ClassName Win32_Process -Filter "Name='dsregcmd.exe'" -OperationTimeoutSec 15 -ErrorAction Stop).Count){$mayRun=$true;throw 'Un dsregcmd peut encore agir.'}
    $effect=[string]$last.Effect;$mayRun=$false
    if($effect -ceq 'Confirmed'){$resultCode=42;$message='Retrait confirmé dans sa preuve cible ; aucun travailleur actif.'}
    elseif($effect -ceq 'NotRequested'){$resultCode=44;$message='Aucun retrait engagé selon la preuve cible.'}
    else{$effect='Uncertain';$resultCode=45;$message='Résultat historique conservé incertain ; absence de travailleur confirmée.'}
  }else{
    if($env:COMPUTERNAME -ine [string]$j.Request.Computer -or [string]$cs[0].Name -ine [string]$j.Request.Computer){throw 'Nom cible différent.'}
    $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
    if($active -ine $j.Request.Computer -or $configured -ine $j.Request.Computer){throw 'Nom Windows changé ou en attente.'}
    if([IO.Directory]::Exists($targetDir)){$mayRun=$true;throw 'Cet identifiant a déjà été engagé : aucun second retrait.'}
    if((Read-Dsreg 90) -cne 'hybrid'){throw 'État hybride confirmé différent : nouvel aperçu requis.'}
    $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')){
      $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    [void][IO.Directory]::CreateDirectory($targetDir,$acl);Set-Acl -LiteralPath $targetDir -AclObject $acl -ErrorAction Stop
    Save-EntraTarget 'LeaveRequested' 'Requested' $true
    $leavePending=$true
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe;$start.Arguments='/leave'
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $native=[Diagnostics.Process]::new();$native.StartInfo=$start
    if(-not $native.Start()){throw 'Réponse de lancement native non confirmée.'}
    $out=$native.StandardOutput.ReadToEndAsync();$err=$native.StandardError.ReadToEndAsync()
    Save-EntraTarget 'LeaveStarted' 'Requested' $true
    if(-not $native.WaitForExit(60000)){$mayRun=$true;throw 'Délai du retrait dépassé ; le processus peut encore terminer.'}
    $null=$out.GetAwaiter().GetResult();$null=$err.GetAwaiter().GetResult()
    $leaveDone=($native.ExitCode -eq 0)
    if(-not $leaveDone){throw 'Retour du retrait non confirmé.'}
    Save-EntraTarget 'LeaveReturnedSuccess' 'Requested' $false
    $valid=$false
    foreach($attempt in 1..2){
      try{if((Read-Dsreg 120) -ceq 'adOnly'){$valid=$true;break}}catch{}
      if($attempt -lt 2){Start-Sleep -Seconds 5}
    }
    if(-not $valid){throw 'Contrôle NO/YES après retrait non confirmé.'}
    Save-EntraTarget 'LeaveConfirmed_ReenrollmentPending' 'Confirmed' $false
    $effect='Confirmed';$mayRun=$false;$resultCode=42
    $message='Retrait Entra confirmé ; réinscription hybride à vérifier séparément. Aucun redémarrage exécuté.'
  }
}catch{
  if($inspection){$effect='Uncertain';$resultCode=97;$mayRun=$true}
  elseif($leavePending -or $leaveDone -or $mayRun){$effect='Uncertain';$resultCode=97}else{$effect='NotRequested';$resultCode=44}
  if($native){try{$mayRun=-not $native.HasExited}catch{$mayRun=$true}}
  $message=if($resultCode -eq 97){'Préparation Entra incertaine ; aucun renommage ni second retrait.'}else{'Précontrôle Entra refusé avant retrait ; nouvel aperçu requis.'}
  if(-not $inspection -and $sequence -gt 0){try{Save-EntraTarget 'Interrupted' $effect $mayRun}catch{}}
}finally{
  if($native){$native.Dispose()}
  if($guard){try{if($owned){$guard.ReleaseMutex()}}finally{$guard.Dispose()}}
}
[Console]::Out.Write((@{Effect=$effect;MayStillRun=$mayRun;Message=$message;NativeCode=$resultCode}|ConvertTo-Json -Compress))
exit $resultCode
""";
}

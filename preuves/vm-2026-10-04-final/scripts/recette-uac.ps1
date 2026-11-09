param([string]$Cas)
$ErrorActionPreference='Stop'
$D='C:\PestoTest-preuves\2026-10-04-final'
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($admin){throw 'Pilote doit etre non eleve'}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$env:ComSpec
$info.Arguments='/d /c C:\PestoTest\VERIFIER_UAC.cmd'
$info.WorkingDirectory='C:\PestoTest-run'
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$p=[Diagnostics.Process]::Start($info)
$handle=$p.Handle
$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync()
@{Date=Get-Date -Format o;Compte=$id.Name;AdminInitial=$admin;CmdPid=$p.Id;Cas=$Cas;ExeSHA256=(Get-FileHash C:\PestoTest\Pesto.exe).Hash} | ConvertTo-Json | Set-Content "$D\uac-$Cas-debut.json" -Encoding UTF8
# L'autorisation ici atteste uniquement qu'une capture UAC a été lue ; l'UAC Windows reste à répondre sur la console.
$gate="$D\uac-$Cas-vue.txt"
$until=[DateTime]::UtcNow.AddMinutes(8)
while(-not $p.HasExited -and [DateTime]::UtcNow -lt $until){
 if(Test-Path $gate){$p.StandardInput.WriteLine('O');$p.StandardInput.WriteLine('');$p.StandardInput.Close();break}
 Start-Sleep -Milliseconds 500
}
if(-not $p.WaitForExit(480000)){throw "Processus conserve : $($p.Id)"}
$out.Result | Set-Content "$D\uac-$Cas-stdout.txt" -Encoding UTF8
$err.Result | Set-Content "$D\uac-$Cas-stderr.txt" -Encoding UTF8
@{Date=Get-Date -Format o;Cas=$Cas;Code=$p.ExitCode;InviteVue=(Test-Path $gate)} | ConvertTo-Json | Set-Content "$D\uac-$Cas-fin.json" -Encoding UTF8
$p.Dispose()

#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
 [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$CertificateThumbprint,
 [Parameter(Mandatory)][uri]$TimestampServer,
 [Parameter(Mandatory)][string]$OutputDirectory,
 [string]$SourceDirectory=(Split-Path $PSScriptRoot -Parent),
 [string]$PythonPath='python'
)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Signature Authenticode : Windows requis.'}
if($TimestampServer.Scheme -ne 'https'){throw 'Serveur horodateur HTTPS approuvé requis.'}
$cert=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$CertificateThumbprint) -ErrorAction Stop
if(-not $cert.HasPrivateKey -or $cert.NotAfter -lt (Get-Date) -or $cert.NotBefore -gt (Get-Date) -or '1.3.6.1.5.5.7.3.3' -notin @($cert.EnhancedKeyUsageList.ObjectId)){throw 'Certificat de signature de code valide avec clé privée requis.'}
$source=[IO.Path]::GetFullPath($SourceDirectory)
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Destination existante : aucun écrasement.'}
if(-not $PSCmdlet.ShouldProcess($output,'Créer une copie DEV, signer les composants propres à Pesto, reconstruire puis vérifier les signatures horodatées')){return}
# package_distribution refuses non-neutral cfg and linked inputs; it never copies user state.
& $PythonPath (Join-Path $source 'tools/package_distribution.py') --source $source --output $output --channel DEV
if($LASTEXITCODE -ne 0){throw 'Préparation de la copie refusée.'}
$stage=Join-Path $output 'DEV'
# Remove the pre-signing archive: this directory is incomplete until all following steps pass.
Get-ChildItem -LiteralPath $output -Filter '*.zip' -File|Remove-Item -Force
$entries=[Collections.Generic.List[object]]::new()
function Sign-OwnedFile {
 param([string]$Path)
 $signature=Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -TimestampServer $TimestampServer.AbsoluteUri -HashAlgorithm SHA256
 $checked=Get-AuthenticodeSignature -LiteralPath $Path
 if($signature.Status -ne 'Valid' -or $checked.Status -ne 'Valid' -or -not $checked.TimeStamperCertificate -or $checked.SignerCertificate.Thumbprint -ne $CertificateThumbprint){throw ('Signature ou horodatage non vérifié : '+[IO.Path]::GetFileName($Path))}
 $entries.Add([pscustomobject]@{Name=$Path.Substring($stage.Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;Signer=$checked.SignerCertificate.Thumbprint;TimestampSigner=$checked.TimeStamperCertificate.Thumbprint;Status=[string]$checked.Status})
}
try {
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $stage 'wad') -File | Where-Object { $_.Name -match '^(Pesto[-.]|Invoke-Pesto)' -and $_.Name -notlike 'Pesto.Engine.*' -and $_.Extension -in @('.ps1','.psm1','.psd1') }){Sign-OwnedFile $file.FullName}
 foreach($folder in @('integrations','tools')){
  $base=Join-Path $stage $folder
  if(Test-Path -LiteralPath $base){foreach($file in Get-ChildItem -LiteralPath $base -Recurse -File|Where-Object{$_.Extension -in @('.ps1','.psm1','.psd1')}){Sign-OwnedFile $file.FullName}}
 }
 # Do not replace the publisher signatures of Microsoft DLLs.
 foreach($file in Get-ChildItem -LiteralPath (Join-Path $stage 'wad') -Filter 'M4D.Admin.Common.*.dll' -File){Sign-OwnedFile $file.FullName}
 $lockPath=Join-Path $stage 'wad/common.lock.json'
 $lock=Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($entry in $lock.Files){$file=Join-Path $stage ('wad/'+$entry.Name);$entry.SHA256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();$entry.Bytes=(Get-Item -LiteralPath $file).Length}
 $lock|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $lockPath -Encoding UTF8
 $engineBuilder=Join-Path $stage 'tools/Build-PestoEngineModule.ps1'
 if(Test-Path -LiteralPath $engineBuilder){
  & $engineBuilder -Root $stage | Out-Null
  Sign-OwnedFile (Join-Path $stage 'wad/Pesto.Engine.Runtime.ps1')
  & $PythonPath (Join-Path $stage 'tools/rebind_signed_engine.py') --root $stage
  if($LASTEXITCODE -ne 0){throw 'Rebinding du Runtime signé refusé.'}
  Sign-OwnedFile (Join-Path $stage 'wad/Pesto.Engine.psm1')
  Sign-OwnedFile (Join-Path $stage 'wad/Pesto.Engine.psd1')
 }
 & $PythonPath (Join-Path $stage 'tools/launcher/build_native.py')
 if($LASTEXITCODE -ne 0){throw 'Compilation native échouée.'}
 Sign-OwnedFile (Join-Path $stage 'Pesto.exe')
 # Keep the unsigned compiler output identity and identify the signed artifact separately.
 $recordPath=Join-Path $stage 'tools/launcher/last-build.json'
 $record=Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json
 $record|Add-Member -NotePropertyName UnsignedSHA256 -NotePropertyValue $record.SHA256
 $record.SHA256=(Get-FileHash -LiteralPath (Join-Path $stage 'Pesto.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
 $record.Size=(Get-Item -LiteralPath (Join-Path $stage 'Pesto.exe')).Length
 $record|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $recordPath -Encoding UTF8
 & $PythonPath (Join-Path $stage 'tools/refresh_manifest.py') --root $stage
 if($LASTEXITCODE -ne 0){throw 'Vérification du manifeste signé échouée.'}
 [ordered]@{Schema=1;Status='SIGNED_AND_VERIFIED_ON_THIS_WINDOWS_HOST';Utc=[DateTime]::UtcNow.ToString('o');Files=$entries.ToArray();WindowsExecution='NOT_RUN';ADExecution='NOT_RUN';TrustInstalled=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'signature.json') -Encoding UTF8
} catch {
 [ordered]@{Schema=1;Status='INCOMPLETE_DO_NOT_DISTRIBUTE';CompletedSignatures=$entries.ToArray()}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'signature.json') -Encoding UTF8
 throw
}

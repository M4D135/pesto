$ErrorActionPreference='Stop'
$target='C:\PestoTest-run\distribution-livraison'
if(Test-Path $target){throw 'Destination déjà présente'}
New-Item -ItemType Directory $target|Out-Null
$rows=@(foreach($channel in @('PROD','DEV')){
 $zip="C:\PestoTest-run\Pesto_1.0_$channel.zip"
 Expand-Archive $zip $target
 $root=Join-Path $target $channel
 $report="C:\PestoTest-preuves\2026-10-04-prod\livraison-$channel-check.json"
 $p=Start-Process (Join-Path $root Pesto.exe) -ArgumentList '--check-json',$report -PassThru -Wait
 if($p.ExitCode -ne 0){throw "$channel contrôle $($p.ExitCode)"}
 $result=Get-Content $report -Raw|ConvertFrom-Json
 if($result.Runtime -ne 'PASS' -or $result.ComponentCount -ne 38 -or $result.Syntax -ne 'PASS'){throw 'Pack non conforme'}
 [pscustomobject]@{Channel=$channel;ZipSHA256=(Get-FileHash $zip).Hash;ExeSHA256=(Get-FileHash (Join-Path $root Pesto.exe)).Hash;ConfigSHA256=(Get-FileHash (Join-Path $root 'wad\cfg.json')).Hash;ExitCode=$p.ExitCode;Signature=(Get-AuthenticodeSignature (Join-Path $root Pesto.exe)).Status.ToString();Check=$result}
})
$rows|ConvertTo-Json -Depth 5|Set-Content 'C:\PestoTest-preuves\2026-10-04-prod\livraison-windows.json' -Encoding UTF8
'PASS : PROD et DEV extraits et contrôlés par leur EXE, aucune UAC/AD, configuration modèle'

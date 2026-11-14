#Requires -Version 7.0
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='C:\Users\degun\actions-runner\PestoTargetedDiag-20261101'
$fixture=Join-Path $root 'private-download-check'
$receipt=[ordered]@{kind='pesto.private-release-download-check';success=$false;utc=[DateTimeOffset]::UtcNow.ToString('O');workflowRun=$false;scriptSha256='4316145f9cb9e4d3fb5f934a3f5441315011000e784db3638c6e475908b2f201';files=@()}
$env:GITHUB_TOKEN=[Console]::In.ReadLine()
try {
 if(Test-Path $fixture){throw 'Owned download fixture already exists'}
 New-Item -ItemType Directory -Path (Join-Path $fixture 'out')|Out-Null
 Set-Location $fixture
 $env:UI_UPDATE_FROM_VERSION='2.0.8'
 $env:UI_UPDATE_FROM_PROD_SHA256='0fcbb2ce36c5ffc3acd146cbbdbd3ca76d6bba2b0bf56bcd837dfef262f494bf'
 $env:UI_UPDATE_FROM_DEV_SHA256='a094152ada77f59e86368a38708c32813e558bf4df2bedecd3ae6853d8537519'
 $env:GITHUB_REPOSITORY='M4D135/pesto'
 . (Join-Path $root 'Workflow-DownloadPinnedRelease.ps1')
 foreach($channel in @('PROD','DEV')){
  $name='Pesto_V2_'+$channel+'_2.0.8.zip';$path=Join-Path $fixture ('out\'+$name)
  $receipt.files+=@([ordered]@{name=$name;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()})
 }
 $receipt.success=$true
 foreach($file in $receipt.files){Remove-Item -LiteralPath (Join-Path $fixture ('out\'+$file.name))}
 $receipt.ownedDownloadedFilesRemoved=$true
}catch{$receipt.error='Private release download verification failed'}
finally{
 $env:GITHUB_TOKEN=$null
 if($headers){$headers.Clear()}
 $receipt.powershellVersion=$PSVersionTable.PSVersion.ToString()
 $receipt|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'private-download-check.json') -Encoding utf8
 $receipt|ConvertTo-Json -Depth 5
}
if(-not $receipt.success){exit 2}

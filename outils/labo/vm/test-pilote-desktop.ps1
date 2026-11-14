# Test du pilote de recette : ne modifie ni compte, ni verrouillage, ni AD.
param([Parameter(Mandatory=$true)][ValidateSet('Blocked','Visible')][string]$Expected, [Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'pilote.psm1') -Force
if(Test-Path $EvidenceDirectory){throw 'Utiliser un dossier de preuves neuf.'}
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$blocked=$false;$detail=''
try { Assert-PestoInteractiveDesktop } catch { $blocked=$true;$detail=$_.Exception.Message }
if($Expected -eq 'Visible'){
  if($blocked){throw $detail}
  Save-Ecran (Join-Path $EvidenceDirectory 'desktop.png')
} else {
  if(-not $blocked){throw 'Le test attendait un bureau inaccessible : aucune capture tentée.'}
  foreach($operation in @('Capture','Invoke','Foreground')){
    $refused=$false
    try {
      switch($operation){
        'Capture' { Save-Ecran (Join-Path $EvidenceDirectory 'unexpected.png') }
        'Invoke' { Invoke-Element $null }
        'Foreground' { Set-Premier $null }
      }
    } catch { $refused=$_.Exception.Message -like 'Recette GUI bloquée*' }
    if(-not $refused){throw "Refus explicite absent : $operation"}
  }
  if(Test-Path (Join-Path $EvidenceDirectory 'unexpected.png')){throw 'Capture produite malgré le blocage.'}
}
[ordered]@{Schema=1;Expected=$Expected;Status='PASS';Blocked=$blocked;Detail=$detail;SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;Utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $EvidenceDirectory 'result.json') -Encoding UTF8
'PASS pilote de recette : '+$Expected

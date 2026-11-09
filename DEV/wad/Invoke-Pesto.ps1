#requires -Version 5.1
<#
.SYNOPSIS
Interface silencieuse Pesto : inspection, préparation et exécution explicite.
.DESCRIPTION
Windows PowerShell 5.1 x64 élevé. Aucun prompt, redémarrage ni secret en argument texte.
Sans -Execute les commandes préparent un plan en lecture seule. -OutPlanPath exporte
un nouveau fichier ; -PlanPath le réutilise après nouveaux contrôles des identités.
-IdempotencyKey protège une demande exécutée contre le rejeu, même après interruption.
Credential et Metadata sont des objets PowerShell fournis par un script appelant.
.EXAMPLE
$r = & .\wad\Invoke-Pesto.ps1 -Action Rename -Computer PC001 -NewName P123456PAINF001 -OutPlanPath C:\Plans\rename.json
.EXAMPLE
$r = & .\wad\Invoke-Pesto.ps1 -Action Rename -PlanPath C:\Plans\rename.json -IdempotencyKey 'campagne42/pc001' -Execute
#>
[CmdletBinding()]
param([ValidateSet('Inspect','Join','Rename','Move','RenameMove','Diagnose')][string]$Action='Inspect',
    [string]$ConfigPath='',$Credential,[string]$Computer='',[string]$NewName='',[string]$TargetOU='',
    [string]$Type='',[string]$SiteCode='',[string]$ServiceCode='',
    [string]$PlanPath='',[string]$OutPlanPath='',[string]$IdempotencyKey='',$Metadata=$null,$Approval=$null,
    [switch]$Execute,[switch]$AsJson
)
$ErrorActionPreference='Stop';Set-StrictMode -Off
. (Join-Path $PSScriptRoot 'Pesto-CliHost.ps1')
try{
    Initialize-PestoCliProcess
    . (Join-Path $PSScriptRoot 'Pesto-Integrity.ps1')
    [void](Test-PestoPackage -Root (Split-Path -Parent $PSScriptRoot))
    Import-Module (Join-Path $PSScriptRoot 'Pesto.Engine.psd1') -ErrorAction Stop
    $call=@{};foreach($k in $PSBoundParameters.Keys){if($k -ne 'AsJson'){$call[$k]=$PSBoundParameters[$k]}}
    $call.RuntimeRoot=$PSScriptRoot
    $result=Invoke-PestoCommand @call
}catch{
    $result=[pscustomobject]@{Schema=1;Mode=$Action;State='NotStarted';ExitCode=96;MutationStarted=$false;RestartRequired=$false;
        OperationId='';Utc=[DateTime]::UtcNow.ToString('o');Message='Démarrage refusé : '+$_.Exception.Message}
}finally{$Credential=$null}
if($AsJson){ConvertTo-PestoCliJson $result 12}else{$result}
exit ([int]$result.ExitCode)

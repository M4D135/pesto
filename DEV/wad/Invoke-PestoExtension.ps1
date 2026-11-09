#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Attributes','OfflineImport','OfflineApply','OfflineObserve','AttributeObserve')][string]$Action,
    [string]$ConfigPath='',$Credential,[Guid]$ObjectGuid=[Guid]::Empty,$Attributes=$null,
    [string]$TargetOU='',[string]$BlobPath='',[string]$BlobId='',[Guid]$OperationId=[Guid]::Empty,
    [string]$PlanPath='',[string]$OutPlanPath='',[string]$IdempotencyKey='',$Metadata=$null,$Approval=$null,
    [switch]$Execute,[switch]$AsJson
)
$ErrorActionPreference='Stop';Set-StrictMode -Off
. (Join-Path $PSScriptRoot 'Pesto-CliHost.ps1')
try{
    Initialize-PestoCliProcess
    . (Join-Path $PSScriptRoot 'Pesto-Integrity.ps1')
    [void](Test-PestoPackage -Root (Split-Path $PSScriptRoot -Parent))
    Import-Module (Join-Path $PSScriptRoot 'Pesto.Engine.psd1') -ErrorAction Stop
    $call=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'AsJson'){$call[$key]=$PSBoundParameters[$key]}};$call.RuntimeRoot=$PSScriptRoot
    $result=Invoke-PestoExtensionCommand @call
}catch{$result=[pscustomobject]@{ExitCode=97;State='Uncertain';Message='Operation interrompue : examiner le recu avant toute nouvelle demande.'}}
finally{$Credential=$null}
if($AsJson){ConvertTo-PestoCliJson $result 12}else{$result}
exit ([int]$result.ExitCode)

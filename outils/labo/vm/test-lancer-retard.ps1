# Double de lecture lente du Planificateur ; aucune tache Windows creee.
param([Parameter(Mandatory=$true)][string]$Lanceur)
$ErrorActionPreference='Stop'
$script:reads=0
function New-ScheduledTaskAction {param($Execute,$Argument,$WorkingDirectory);return [pscustomobject]@{}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel);return [pscustomobject]@{}}
function New-ScheduledTaskSettingsSet {param([switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,$ExecutionTimeLimit,$MultipleInstances);return [pscustomobject]@{}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$Settings)}
function Start-ScheduledTask {param($TaskName)}
function Get-ScheduledTask {param($TaskName);return [pscustomobject]@{State='Ready'}}
function Get-ScheduledTaskInfo {
 param($TaskName)
 $script:reads++
 if($script:reads -eq 1){return [pscustomobject]@{LastRunTime=[datetime]::MinValue;LastTaskResult=267011}}
 Start-Sleep -Milliseconds 1500
 return [pscustomobject]@{LastRunTime=[datetime]'2026-10-04';LastTaskResult=0}
}
function Unregister-ScheduledTask {param($TaskName,$Confirm);'DOUBLE : definition retiree'}
& $Lanceur -Exe cmd.exe -Attendre -Delai 1
$code=$LASTEXITCODE
"Code observe=$code ; attendu=1 (resultat 0 revenu trop tard)"
if($code -ne 1){exit 1}
exit 0

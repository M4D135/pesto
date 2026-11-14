param([string]$Suite,[switch]$Wpf)
$ErrorActionPreference='Stop'
if((Get-Process -Id $PID).SessionId -ne 0){throw 'UI audit requires isolated session 0'}
# Last-resort traps supplement each suite's own local fixtures.
function global:Add-Computer {throw 'AUDIT: real machine mutation forbidden'}
function global:Rename-Computer {throw 'AUDIT: real machine mutation forbidden'}
function global:Restart-Computer {throw 'AUDIT: real machine mutation forbidden'}
function global:Remove-Computer {throw 'AUDIT: real machine mutation forbidden'}
function global:Move-ADObject {throw 'AUDIT: real AD mutation forbidden'}
function global:Set-ADObject {throw 'AUDIT: real AD mutation forbidden'}
function global:Remove-ADObject {throw 'AUDIT: real AD mutation forbidden'}
function global:Get-ADComputer {throw 'AUDIT: real AD read forbidden'}
function global:Get-ADOrganizationalUnit {throw 'AUDIT: real AD read forbidden'}
function global:Get-CimInstance {throw 'AUDIT: real machine read forbidden'}
$arguments=@{ReportPath=($PSScriptRoot+'\reports\'+$Suite+'.json')}
if($Wpf){$arguments.Wpf=$true}
& ($PSScriptRoot+'\tests\Run-'+$Suite+'Tests.ps1') @arguments
if($null -ne $LASTEXITCODE){exit $LASTEXITCODE}

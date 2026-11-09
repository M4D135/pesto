#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param()
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne 'Win32NT'){throw 'Provisionnement disponible sur Windows uniquement.'}
if([Diagnostics.EventLog]::SourceExists('Pesto')){
    if([Diagnostics.EventLog]::LogNameFromSourceName('Pesto','.') -cne 'Application'){throw 'La source Pesto existe dans un autre journal. Aucun changement effectue.'}
    Write-Output 'La source Pesto existe deja dans le journal Application.'
    return
}
if($PSCmdlet.ShouldProcess('Journal Application / source Pesto','Declarer la source d audit')){
    New-EventLog -LogName Application -Source Pesto -ErrorAction Stop
    if(-not [Diagnostics.EventLog]::SourceExists('Pesto') -or [Diagnostics.EventLog]::LogNameFromSourceName('Pesto','.') -cne 'Application'){throw 'Source non confirmee apres creation.'}
    Write-Output 'Source Pesto declaree dans le journal Application. Activer ensuite le reglage dans Pesto.'
}

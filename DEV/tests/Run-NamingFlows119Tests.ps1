#requires -Version 5.1
param()
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'wad/Pesto.Engine.Runtime.ps1')
. (Join-Path $root 'wad/Pesto-Review.ps1')
. (Join-Path $root 'wad/Pesto-Join.ps1')
$script:pass=0;$script:fail=0
function Case($name,[scriptblock]$body){try{&$body;$script:pass++}catch{$script:fail++;Write-Host ('FAIL '+$name+': '+$_)}}
function Assert($value){if(-not$value){throw 'Assertion failed'}}
$custom=[pscustomobject]@{Schema=1;Id='middle';Tokens=@('Service','Number','Type','Prefix','Site');Widths=@{Prefix=3;Site=2;Service=2;Number=2};Types='PSV'}
[void](Set-PestoActiveNamingConvention $custom)
$computers=@([pscustomobject]@{Name='IT01P123AB'},[pscustomobject]@{Name='IT99P123AB'})
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
try{
 Case 'Taken custom names stay excluded in the session' {$script:PestoTakenNames=$null;Add-PestoTakenNames @('IT01P123AB','invalid');Assert ($script:PestoTakenNames.Count -eq 1 -and $script:PestoTakenNames.Contains('IT01P123AB'))}
 Case 'Available names use number in middle and exclude endpoints' {$r=Get-AvailableMachines $computers P123 AB IT;Assert ($r.Count -eq 97 -and $r[0] -eq 'IT02P123AB' -and $r[-1] -eq 'IT98P123AB')}
 Case 'Custom field widths reach form validation and configured tags' {$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='AB'})};$r=Get-NameList Paris IT $computers P123;Assert ($r.Count -eq 97)}
 $q=[pscustomobject]@{Generation=1;Computers=$computers;Prefix='123';ReservedNames=@('IT02P123AB');Types=@('P');Sites=@('AB');Teams=@('IT');Status='Tous';Search='';ShowAll=$true;PageSize=10;Offset=0;Buffer=2;RandomEnabled=$false;Cancellation=$null;CachedIndex=$null;Strategy='FirstGap'}
 Case 'Names view uses custom capacity, reserved status and number formatting' {$r=Invoke-PestoBuildNamesView $q;Assert ($r.Total -eq 99 -and $r.CandidateCount -eq 96 -and $r.Rows[1].Nom -eq 'IT02P123AB' -and $r.Rows[1].Reserved -and $r.Rows[2].Num -eq '03')}
 Case 'Fresh runspace receives naming definitions and current convention' {$ps=[Management.Automation.PowerShell]::Create();try{[void]$ps.AddScript((Get-PestoPreflightSource)+"`n(New-PestoComputerName -Type P -Prefix 123 -Site AB -Service IT -Number 3)");$r=$ps.Invoke();Assert ($ps.Streams.Error.Count -eq 0 -and $r[-1] -eq 'IT03P123AB')}finally{$ps.Dispose()}}
 Case 'Names worker source works in an empty runspace' {$source='param($Request)'+[Environment]::NewLine+(Get-PestoNamingContextSource)+'function Invoke-PestoBuildNamesView {'+(Get-Command Invoke-PestoBuildNamesView).Definition+'}'+[Environment]::NewLine+'Invoke-PestoBuildNamesView $Request';$ps=[Management.Automation.PowerShell]::Create();try{[void]$ps.AddScript($source).AddArgument($q);$r=$ps.Invoke();Assert ($ps.Streams.Error.Count -eq 0 -and $r[0].Total -eq 99)}finally{$ps.Dispose()}}
 Case 'LDAP conflict pattern tracks number position' {$filter=New-PestoNameConflictFilter @('ITP123AB');Assert ($filter.Contains('(name=IT*P123AB*)') -and -not $filter.Contains('ITP123AB*'))}
 Case 'Capacity uses configured maximum and occupied identities' {$rows=@(Get-PestoCapacityRows $computers @() @('IT02P123AB') '123' $null);Assert ($rows.Count -eq 1 -and $rows[0].Capacite -eq 99 -and $rows[0].Libres -eq 96)}
 Case 'Cache invalidated on convention replacement' {$null=Get-PestoNameInventoryIndex $computers;[void](Set-PestoActiveNamingConvention $null);$r=Get-PestoNameInventoryIndex $computers;Assert ($r.Entries.Count -eq 0);[void](Set-PestoActiveNamingConvention $custom)}
 Case 'Automation enumerates the configured series' {function Get-ADParams {@{}};function Get-ADComputer {param($LDAPFilter,$SearchBase,$SearchScope,$Properties,$ResultSetSize,$ErrorAction);$script:filter=$LDAPFilter;return $computers};$script:PREFIXE='123';$script:PestoPolicy=[pscustomobject]@{ExcludedNames=@()};$r=Get-PestoAutomationCandidates P AB IT 'DC=example,DC=local';Assert ($r.Count -eq 97 -and $r[0] -eq 'IT02P123AB' -and $script:filter.Contains('IT*P123AB'))}
 Case 'Configuration rejects prefix inconsistent with its own convention' {$cfg=Get-Content (Join-Path $root 'tools/cfg.modele-complet.json') -Raw|ConvertFrom-Json;$cfg|Add-Member NamingConvention $custom;$errors=@(Test-CfgValid $cfg);Assert (@($errors|Where-Object{$_ -match 'Préfixe invalide'}).Count -eq 1)}
}finally{[void](Set-PestoActiveNamingConvention $null)}
Write-Host "NamingFlows119: $script:pass passed, $script:fail failed; empty local runspaces, no AD/VM."
if($script:fail){exit 1}

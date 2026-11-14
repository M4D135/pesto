#requires -Version 5.1
param([Parameter(Mandatory)][string]$BundleDirectory,[Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Windows STA required.'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[void][Reflection.Assembly]::LoadFrom((Join-Path $BundleDirectory 'M4D.Admin.Common.Wpf.dll'))
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{Name=$Name;Passed=$Ok});if(-not $Ok){throw $Name}}
Check 'lower bound' ([M4D.Admin.Common.Wpf.Presentation]::Bound(0,80,150) -eq 80)
Check 'upper bound' ([M4D.Admin.Common.Wpf.Presentation]::Bound(200,80,150) -eq 150)
Check 'fraction retained' ([M4D.Admin.Common.Wpf.Presentation]::Bound(110.5,80,150) -eq 110.5)
Check 'NaN fallback' ([M4D.Admin.Common.Wpf.Presentation]::Bound([double]::NaN,80,150) -eq 80)
$button=New-Object Windows.Controls.Button
[M4D.Admin.Common.Wpf.Presentation]::RefreshExistingPeer($button)
Check 'no peer created' ($null -eq [Windows.Automation.Peers.UIElementAutomationPeer]::FromElement($button))
$script:count=0;$dispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher
$coalescer=New-Object M4D.Admin.Common.Wpf.DispatcherCoalescer($dispatcher,[Action]{$script:count++})
$coalescer.Request();$coalescer.Request();$coalescer.Request()
$frame=New-Object Windows.Threading.DispatcherFrame
[void]$dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false})
[Windows.Threading.Dispatcher]::PushFrame($frame)
Check 'requests coalesced' ($script:count -eq 1)
$coalescer.Request();$coalescer.Dispose()
$frame=New-Object Windows.Threading.DispatcherFrame
[void]$dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false})
[Windows.Threading.Dispatcher]::PushFrame($frame)
Check 'dispose cancels pending' ($script:count -eq 1)
[ordered]@{Schema=1;Scope='Windows WPF isolated';SHA256=(Get-FileHash -LiteralPath (Join-Path $BundleDirectory 'M4D.Admin.Common.Wpf.dll') -Algorithm SHA256).Hash;Checks=$checks.ToArray();ADExecuted=$false;ApplicationExecuted=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $ReportPath -Encoding UTF8

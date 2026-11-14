#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][int]$TargetProcessId,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ReportDirectory)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Capture Windows interactive requise.'}
if(Test-Path -LiteralPath $ReportDirectory){throw 'Choisir un dossier neuf.'}
Add-Type -AssemblyName System.Drawing,System.Windows.Forms,UIAutomationClient,UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PestoCaptureNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
}
'@
$process=Get-Process -Id $TargetProcessId -ErrorAction Stop
$window=$process.MainWindowHandle
if($window -eq [IntPtr]::Zero -or [PestoCaptureNative]::GetForegroundWindow() -ne $window){throw 'La fenêtre cible doit être visible au premier plan ; aucune capture derrière verrouillage.'}
$rect=New-Object PestoCaptureNative+RECT
if(-not [PestoCaptureNative]::GetWindowRect($window,[ref]$rect)){throw 'Rectangle indisponible.'}
$width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top
if($width -lt 1 -or $height -lt 1 -or $width -gt 10000 -or $height -gt 10000){throw 'Rectangle de capture invalide.'}
[void][IO.Directory]::CreateDirectory($ReportDirectory)
$bitmap=New-Object Drawing.Bitmap($width,$height);$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,$bitmap.Size);$bitmap.Save((Join-Path $ReportDirectory 'window.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
$element=[Windows.Automation.AutomationElement]::FromHandle($window)
$all=$element.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$rows=@(for($index=0;$index -lt [Math]::Min(1000,$all.Count);$index++){$item=$all.Item($index).Current;[pscustomobject]@{Id=$item.AutomationId;Control=[string]$item.ControlType.ProgrammaticName;Enabled=$item.IsEnabled;Offscreen=$item.IsOffscreen;Bounds=[string]$item.BoundingRectangle}})
[ordered]@{Schema=1;BuildIdentitySource='SUPPLIED_ROOT_NOT_PROCESS_ATTESTED';BuildSHA256=(Get-FileHash -LiteralPath (Join-Path $Root 'Pesto.exe') -Algorithm SHA256).Hash;Utc=[DateTime]::UtcNow.ToString('o');ForegroundVerified=$true;Width=$width;Height=$height;Controls=$rows;Truncated=($all.Count -gt 1000);ActionsInvoked=$false;Verdict='CAPTURE_ONLY_REQUIRES_REVIEW';ImageSHA256=(Get-FileHash -LiteralPath (Join-Path $ReportDirectory 'window.png') -Algorithm SHA256).Hash}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $ReportDirectory 'capture.json') -Encoding UTF8

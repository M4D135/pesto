[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceCommit
)
$ErrorActionPreference = 'Stop'
# Observation only: no process is started/stopped and no absence changes native test criteria.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PestoDesktopObservation {
    [DllImport("user32.dll", ExactSpelling = true)]
    public static extern IntPtr GetShellWindow();
    [DllImport("user32.dll", ExactSpelling = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
'@
$current = [Diagnostics.Process]::GetCurrentProcess()
try { $session = $current.SessionId } finally { $current.Dispose() }
$shellWindow = [PestoDesktopObservation]::GetShellWindow()
[uint32]$shellProcessId = 0
$shellSessionId = $null
$shellThreadId = 0
if ($shellWindow -ne [IntPtr]::Zero) {
    $shellThreadId = [PestoDesktopObservation]::GetWindowThreadProcessId($shellWindow, [ref]$shellProcessId)
    if ($shellProcessId -ne 0) {
        $shellProcess = Get-Process -Id $shellProcessId -ErrorAction SilentlyContinue
        if ($null -ne $shellProcess) {
            try { $shellSessionId = $shellProcess.SessionId } finally { $shellProcess.Dispose() }
        }
    }
}
$explorers = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
try { $explorerCount = @($explorers | Where-Object { $_.SessionId -eq $session }).Count }
finally { foreach ($process in $explorers) { $process.Dispose() } }
$observation = [ordered]@{
    schemaVersion = 1
    kind = 'pesto.windows-desktop-observation'
    observationOnly = $true
    utc = [DateTimeOffset]::UtcNow.ToString('O')
    sourceCommit = $SourceCommit
    ciProcessId = $PID
    ciSessionId = $session
    userInteractive = [Environment]::UserInteractive
    shellWindowPresent = $shellWindow -ne [IntPtr]::Zero
    shellProcessId = $shellProcessId
    shellThreadId = $shellThreadId
    shellSessionId = $shellSessionId
    explorerCountInSession = $explorerCount
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($observation | ConvertTo-Json -Depth 3) + "`n", [Text.UTF8Encoding]::new($false))

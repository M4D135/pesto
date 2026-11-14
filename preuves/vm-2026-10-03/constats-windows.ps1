# constats-windows.ps1 - PowerShell 5.1 only. UTF-8 BOM/CRLF requis.
param(
 [string]$Source = 'C:\PestoTest',
 [string]$Base = 'C:\PC',
 [string]$Sortie = ''
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if([string]::IsNullOrWhiteSpace($Sortie)){ $Sortie = Join-Path $Base 'constats-windows.txt' }
try { New-Item -ItemType Directory -Force -Path $Base | Out-Null } catch { Write-Host ('Impossible de creer Base: ' + $_.Exception.Message); exit 1 }
$BaseFull = [System.IO.Path]::GetFullPath($Base)
$SourceFull = [System.IO.Path]::GetFullPath($Source)
$Sortie = [System.IO.Path]::GetFullPath($Sortie)
function Test-UnderPath([string]$Root,[string]$Path){
 $rootFull = [System.IO.Path]::GetFullPath($Root)
 $pathFull = [System.IO.Path]::GetFullPath($Path)
 $sep = [System.IO.Path]::DirectorySeparatorChar.ToString()
 $prefix = $rootFull
 if(-not $prefix.EndsWith($sep)){ $prefix = $prefix + $sep }
 if($pathFull -eq $rootFull){ return $true }
 return $pathFull.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)
}
if(Test-UnderPath $SourceFull $BaseFull){ Write-Host 'Base sous Source: refus'; exit 1 }
if(Test-UnderPath $SourceFull $Sortie){ $Sortie = Join-Path $BaseFull 'constats-windows.txt' }
$SortieDir = Split-Path -Parent $Sortie
if($SortieDir -and -not (Test-Path -LiteralPath $SortieDir)){
 try { New-Item -ItemType Directory -Force -Path $SortieDir | Out-Null } catch { Write-Host ('Impossible de creer dossier Sortie: ' + $_.Exception.Message); exit 1 }
}
try { Set-Content -LiteralPath $Sortie -Value ('Pesto constats ' + (Get-Date).ToString('s')) -Encoding UTF8 } catch { Write-Host ('Impossible de creer Sortie: ' + $_.Exception.Message); exit 1 }
function Write-Line([string]$Id,[string]$Message){
 $line = $Id + ' ' + $Message
 try { Add-Content -LiteralPath $Sortie -Value $line -Encoding UTF8 } catch { Write-Host ('Ecriture sortie impossible: ' + $_.Exception.Message) }
 Write-Host $line
}
function Get-SafePath([string]$Path){
 $full = [System.IO.Path]::GetFullPath($Path)
 $sep = [System.IO.Path]::DirectorySeparatorChar.ToString()
 $prefix = $BaseFull
 if(-not $prefix.EndsWith($sep)){ $prefix = $prefix + $sep }
 if($full -eq $BaseFull){ throw 'Refus de toucher Base directement' }
 if(-not $full.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)){ throw ('Hors Base: ' + $Path) }
 return $full
}
function Remove-UnderBase([string]$Path){
 $safe = Get-SafePath $Path
 if(Test-Path -LiteralPath $safe){ Remove-Item -LiteralPath $safe -Recurse -Force }
}
function New-TestDir([string]$Path){
 $safe = Get-SafePath $Path
 Remove-UnderBase $safe
 New-Item -ItemType Directory -Force -Path $safe | Out-Null
 return $safe
}
function Copy-Pack([string]$Dir){
 $exe = Join-Path $SourceFull 'Pesto.exe'
 $wad = Join-Path $SourceFull 'wad'
 if(-not (Test-Path -LiteralPath $exe)){ Write-Line 'COPY' 'Pesto.exe absent dans Source'; return $false }
 if(-not (Test-Path -LiteralPath $wad)){ Write-Line 'COPY' 'wad absent dans Source'; return $false }
 $safe = New-TestDir $Dir
 Copy-Item -LiteralPath $exe -Destination (Join-Path $safe 'Pesto.exe') -Force
 Copy-Item -LiteralPath $wad -Destination (Join-Path $safe 'wad') -Recurse -Force
 return $true
}
function Invoke-External([string]$File,[string[]]$Arguments,[string]$Id,[string]$Label){
 if(-not (Test-Path -LiteralPath $File)){ Write-Line $Id ($Label + ' absent'); return $null }
 $code = $null
 $out = ''
 try {
  $out = & $File @Arguments 2>&1 | Out-String
  $code = $LASTEXITCODE
 } catch { $out = $_.Exception.Message }
 if($null -eq $out){ $out = '' }
 if($null -eq $code){ $code = 'null' }
 $out = $out -replace '\s+',' '
 Write-Line $Id ($Label + '=' + $code + ' ' + $out)
 return $code
}
function Invoke-Pesto([string]$Dir,[string]$Id,[string]$Attendu){
 $exe = Join-Path $Dir 'Pesto.exe'
 if(-not (Test-Path -LiteralPath $exe)){ Write-Line $Id 'Pesto.exe absent'; return $null }
 try {
  $proc = Start-Process -FilePath $exe -ArgumentList @('--check','--quiet') -WorkingDirectory $Dir -WindowStyle Hidden -PassThru
  if(-not $proc.WaitForExit(60000)){
   try { $proc.Kill() } catch {}
   $proc.WaitForExit()
  }
  $code = $proc.ExitCode
  $proc.Dispose()
  if($null -eq $code){ $code = 'null' }
  Write-Line $Id ('exit=' + $code + ' attendu=' + $Attendu)
  return $code
 } catch {
  Write-Line $Id ('erreur=' + $_.Exception.Message)
  return $null
 }
}
$compact = Join-Path $env:SystemRoot 'System32\compact.exe'
$fsutil = Join-Path $env:SystemRoot 'System32\fsutil.exe'
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
# L1a
try {
 $dir = Join-Path $BaseFull 'L1a-wof-file'
 if(Copy-Pack $dir){
  $file = Join-Path $dir 'wad\Pesto-Core.ps1'
  if(Test-Path -LiteralPath $file){
   Invoke-External $compact @('/c','/exe:xpress4k',$file) 'L1a' 'compact' | Out-Null
   Invoke-External $fsutil @('reparsepoint','query',$file) 'L1a' 'fsutil' | Out-Null
   Invoke-Pesto $dir 'L1a' '0' | Out-Null
  } else { Write-Line 'L1a' 'wad\Pesto-Core.ps1 absent' }
 }
} catch { Write-Line 'L1a' ('erreur=' + $_.Exception.Message) }
# L1b
try {
 $dir = Join-Path $BaseFull 'L1b-wof-folder'
 if(Copy-Pack $dir){
  $wad = Join-Path $dir 'wad'
  if(Test-Path -LiteralPath $wad){
   Invoke-External $compact @('/c',$wad) 'L1b' 'compact' | Out-Null
   Invoke-Pesto $dir 'L1b' 'temoin' | Out-Null
  } else { Write-Line 'L1b' 'wad absent' }
 }
} catch { Write-Line 'L1b' ('erreur=' + $_.Exception.Message) }
# L1c
try {
 $dir = Join-Path $BaseFull 'L1c-symlink-file'
 if(Copy-Pack $dir){
  $outside = Join-Path $BaseFull 'L1c-outside'
  $outsideFile = Join-Path $outside 'Pesto-Core.ps1'
  $sourceFile = Join-Path $SourceFull 'wad\Pesto-Core.ps1'
  if(Test-Path -LiteralPath $sourceFile){
   New-TestDir $outside | Out-Null
   Copy-Item -LiteralPath $sourceFile -Destination $outsideFile -Force
   $file = Join-Path $dir 'wad\Pesto-Core.ps1'
   if(Test-Path -LiteralPath $file){ Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
   try {
    New-Item -ItemType SymbolicLink -Path $file -Target $outsideFile -Force | Out-Null
    Write-Line 'L1c' ('lien=' + $file + ' cible=' + $outsideFile)
   } catch { Write-Line 'L1c' ('creation lien impossible=' + $_.Exception.Message) }
   Invoke-Pesto $dir 'L1c' '!=0' | Out-Null
  } else { Write-Line 'L1c' 'source wad\Pesto-Core.ps1 absent' }
 }
} catch { Write-Line 'L1c' ('erreur=' + $_.Exception.Message) }
# L1d
try {
 $dir = Join-Path $BaseFull 'L1d-junction-folder'
 if(Copy-Pack $dir){
  $wad = Join-Path $dir 'wad'
  $real = Join-Path $dir 'wad-real'
  if(Test-Path -LiteralPath $wad){
   try {
    Rename-Item -LiteralPath $wad -NewName 'wad-real' -Force
    Write-Line 'L1d' ('renommage=' + $wad + ' -> ' + $real)
   } catch { Write-Line 'L1d' ('renommage impossible=' + $_.Exception.Message) }
   if((Test-Path -LiteralPath $real) -and -not (Test-Path -LiteralPath $wad)){
    Invoke-External $cmdExe @('/d','/c','mklink','/J',$wad,$real) 'L1d' 'mklink' | Out-Null
   } else { Write-Line 'L1d' 'preconditions jonction absentes' }
   Invoke-Pesto $dir 'L1d' '!=0' | Out-Null
  } else { Write-Line 'L1d' 'wad absent' }
 }
} catch { Write-Line 'L1d' ('erreur=' + $_.Exception.Message) }
# L2
try {
 $dir = Join-Path $BaseFull 'L2-rename'
 if(Copy-Pack $dir){
  $exe = Join-Path $dir 'Pesto.exe'
  if(Test-Path -LiteralPath $exe){
   $proc = Start-Process -FilePath $exe -ArgumentList @('--check','--quiet') -WorkingDirectory $env:SystemRoot -WindowStyle Hidden -PassThru
   $start = Get-Date
   $deadline = $start.AddSeconds(30)
   $ok = 0
   $fail = 0
   $last = 'none'
   $cur = $dir
   $target = $dir + '.renamed'
   $leafTarget = [System.IO.Path]::GetFileName($target)
   $leafCur = [System.IO.Path]::GetFileName($cur)
   while(-not $proc.HasExited -and (Get-Date) -lt $deadline){
    try {
     Rename-Item -LiteralPath $cur -NewName $leafTarget -ErrorAction Stop
     $ok++
     $last = 'rename ok'
     $old = $cur
     $cur = $target
     Rename-Item -LiteralPath $cur -NewName $leafCur -ErrorAction Stop
     $last = 'rename back ok'
     $cur = $old
    } catch {
     $fail++
     $last = $_.Exception.Message
    }
    Start-Sleep -Milliseconds 20
   }
   if(-not $proc.HasExited){
    try { $proc.Kill() } catch {}
   }
   $proc.WaitForExit()
   $code = $proc.ExitCode
   $proc.Dispose()
   $duration = (Get-Date) - $start
   if($null -eq $code){ $code = 'null' }
   $last = $last -replace '\r?\n',' '
   Write-Line 'L2' ('ok=' + $ok + ' refus=' + $fail + ' duree=' + $duration.TotalSeconds + ' exit=' + $code + ' dernier=' + $last)
  } else { Write-Line 'L2' 'Pesto.exe absent' }
 }
} catch { Write-Line 'L2' ('erreur=' + $_.Exception.Message) }
# O12
$names = @('O12 normal','O12 a^b','O12 c%PATH%d')
foreach($name in $names){
 $id = 'O12 ' + $name
 try {
  $dir = Join-Path $BaseFull $name
  New-TestDir $dir | Out-Null
  $srcCmd = Join-Path $SourceFull 'Pesto_COMPTE_AD.cmd'
  if(-not (Test-Path -LiteralPath $srcCmd)){ Write-Line $id 'Pesto_COMPTE_AD.cmd absent dans Source'; continue }
  Copy-Item -LiteralPath $srcCmd -Destination (Join-Path $dir 'Pesto_COMPTE_AD.cmd') -Force
  $doublePath = Join-Path $dir 'Pesto.cmd'
  $double = @(
   '@echo off',
   'setlocal EnableExtensions DisableDelayedExpansion',
   '>"%~dp0sortie.txt" echo "dp0=[%~dp0]"',
   '>>"%~dp0sortie.txt" echo "args=[%*]"',
   'exit /b 7'
  )
  Set-Content -LiteralPath $doublePath -Value $double -Encoding ASCII
  $proc = Start-Process -FilePath $cmdExe -ArgumentList @('/d','/c','Pesto_COMPTE_AD.cmd','-X') -WorkingDirectory $dir -WindowStyle Hidden -PassThru
  if(-not $proc.WaitForExit(30000)){
   try { $proc.Kill() } catch {}
   $proc.WaitForExit()
  }
  $code = $proc.ExitCode
  $proc.Dispose()
  if($null -eq $code){ $code = 'null' }
  $outFile = Join-Path $dir 'sortie.txt'
  $content = 'absent'
  if(Test-Path -LiteralPath $outFile){ $content = Get-Content -LiteralPath $outFile -Raw }
  if($null -eq $content){ $content = 'vide' }
  if($content -eq ''){ $content = 'vide' }
  $content = $content -replace '\r?\n',' | '
  Write-Line $id ('exit=' + $code + ' attendu=7 sortie=' + $content)
 } catch { Write-Line $id ('erreur=' + $_.Exception.Message) }
}
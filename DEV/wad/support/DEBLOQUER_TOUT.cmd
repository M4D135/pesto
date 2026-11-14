@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PESTO_UNBLOCK_SELF=%~f0"
set "PESTO_UNBLOCK_DIR=%~dp0"
set "PESTO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PESTO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PESTO_PS%" (
  echo Windows PowerShell est introuvable.
  pause
  exit /b 2
)
"%PESTO_PS%" -NoLogo -NoProfile -Command "$s=[IO.File]::ReadAllText($env:PESTO_UNBLOCK_SELF); $m=':__PESTO_SUPPORT_POWERSHELL__'; $i=$s.LastIndexOf($m,[StringComparison]::Ordinal); if($i -lt 0){exit 2}; & ([scriptblock]::Create($s.Substring($i+$m.Length)))"
set "PESTO_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %PESTO_EXIT%
:__PESTO_SUPPORT_POWERSHELL__
$ErrorActionPreference='Stop'
$failed=0; $unblocked=0; $already=0; $skipped=0
$entries=New-Object 'System.Collections.Generic.List[string]'
try {
    $support=Get-Item -LiteralPath $env:PESTO_UNBLOCK_DIR -Force
    if(-not $support.PSIsContainer -or $support.Name -ine 'support' -or $support.Parent.Name -ine 'wad') {
        throw 'Ce fichier doit rester dans wad\support.'
    }
    $root=$support.Parent.Parent
    if($null -eq $root -or $null -eq $root.Parent -or $root.FullName -eq [IO.Path]::GetPathRoot($root.FullName)) {
        throw 'Racine de deblocage refusee.'
    }
    # Do not traverse junctions, links or a redirected ancestor.
    $ancestor=$support
    while($null -ne $ancestor) {
        if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Chemin redirige refuse : '+$ancestor.FullName)
        }
        $ancestor=$ancestor.Parent
    }
    foreach($relative in @('Pesto.exe','wad\Pesto-Startup.ps1','wad\Pesto-Core.ps1')) {
        $target=Get-Item -LiteralPath ([IO.Path]::Combine($root.FullName,$relative)) -Force
        if($target.PSIsContainer -or (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw ('Composant invalide : '+$relative)
        }
    }
    Write-Host 'Pesto - Debloquer les fichiers de cette installation'
    Write-Host ('Dossier : '+$root.FullName)
    Write-Host 'Retire uniquement les marques de telechargement des fichiers.'
    Write-Host 'Ne modifie ni antivirus, ni strategies Windows, ni droits, ni verrous Pesto.'
    if((Read-Host 'Confirmer la provenance de ces fichiers et continuer ? O/N') -ine 'O') { exit 0 }
    # Premier niveau : seulement les elements du pack Pesto (PROD ou DEV). Un pack extrait dans un dossier
    # partage (Telechargements, Bureau) ne debloque pas les fichiers voisins. # PESTO_ROOT_FILTER
    $isPestoEntry={param($Name,[bool]$Folder) if($Folder){return $Name -in @('wad','tools','tests','docs','changes','integrations','.github','vendor','src')}; return ($Name -in @('Pesto.exe','README.md','LIRE_MOI.txt','CHANGELOG.md','.gitignore','.gitattributes','pytest.ini')) -or ($Name -match '^(Pesto[A-Za-z0-9_]*|DEMO[A-Za-z0-9_]*|APERCU_LOGIN|ETAT_RENOMMAGE|TEST[A-Za-z0-9_]*|VERIFIER[A-Za-z0-9_]*|FABRIQUER_PACKS|FABRIQUER_PROD)\.cmd$')}
    $pending=New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    try { $top=@(Get-ChildItem -LiteralPath $root.FullName -Force -ErrorAction Stop) }
    catch { throw ('Enumeration impossible : '+$root.FullName) }
    foreach($item in $top) {
        if(-not (& $isPestoEntry $item.Name ([bool]$item.PSIsContainer))) {$skipped++; $entries.Add('HORS PESTO IGNORE '+$item.FullName); continue}
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {$skipped++; $entries.Add('LIEN IGNORE '+$item.FullName); continue}
        if($item.PSIsContainer) {$pending.Push($item); continue}
        try {
            $streams=@(Get-Item -LiteralPath $item.FullName -Stream '*' -Force -ErrorAction Stop)
            if(@($streams | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -eq 0) {$already++;continue}
            Unblock-File -LiteralPath $item.FullName -ErrorAction Stop
            $after=@(Get-Item -LiteralPath $item.FullName -Stream '*' -Force -ErrorAction Stop)
            if(@($after | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -gt 0) {throw 'La marque est toujours presente.'}
            $unblocked++; $entries.Add('DEBLOQUE '+$item.FullName)
        } catch {$failed++; $entries.Add('ERREUR '+$item.FullName+' : '+$_.Exception.Message)}
    }
    while($pending.Count -gt 0) {
        $dir=$pending.Pop()
        try { $items=@(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop) }
        catch { $failed++; $entries.Add('ERREUR ENUMERATION '+$dir.FullName+' : '+$_.Exception.Message); continue }
        foreach($item in $items) {
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $skipped++; $entries.Add('LIEN IGNORE '+$item.FullName); continue
            }
            if($item.PSIsContainer) { $pending.Push($item); continue }
            try {
                $streams=@(Get-Item -LiteralPath $item.FullName -Stream '*' -Force -ErrorAction Stop)
                if(@($streams | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -eq 0) {$already++;continue}
                Unblock-File -LiteralPath $item.FullName -ErrorAction Stop
                $after=@(Get-Item -LiteralPath $item.FullName -Stream '*' -Force -ErrorAction Stop)
                if(@($after | Where-Object {$_.Stream -eq 'Zone.Identifier'}).Count -gt 0) {throw 'La marque est toujours presente.'}
                $unblocked++; $entries.Add('DEBLOQUE '+$item.FullName)
            } catch {$failed++; $entries.Add('ERREUR '+$item.FullName+' : '+$_.Exception.Message)}
        }
    }
    $summary='Debloques={0}; deja sans marque={1}; liens ou hors Pesto ignores={2}; erreurs={3}' -f $unblocked,$already,$skipped,$failed
    Write-Host $summary
    $entries.Insert(0,([DateTime]::UtcNow.ToString('o')+' '+$summary))
    try {
        $logdir=[IO.Path]::Combine($root.FullName,'wad\logs')
        if(Test-Path -LiteralPath $logdir) {
            $ld=Get-Item -LiteralPath $logdir -Force
            if(-not $ld.PSIsContainer -or (($ld.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {throw 'Dossier de journal non sur.'}
        } else {[void][IO.Directory]::CreateDirectory($logdir)}
        $log=[IO.Path]::Combine($logdir,('DEBLOCAGE_Pesto_'+[DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')+'_'+[Guid]::NewGuid().ToString('N')+'.log'))
        $stream=New-Object IO.FileStream($log,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $bytes=(New-Object Text.UTF8Encoding($true)).GetBytes(($entries -join [Environment]::NewLine))
            $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true)
        } finally {$stream.Dispose()}
        Write-Host ('Journal : '+$log)
    } catch {$failed++;Write-Warning ('Le bilan ne peut pas etre enregistre : '+$_.Exception.Message)}
    if($failed -gt 0) {exit 1}
    exit 0
} catch {Write-Host ('Deblocage non termine : '+$_.Exception.Message) -ForegroundColor Red;exit 2}

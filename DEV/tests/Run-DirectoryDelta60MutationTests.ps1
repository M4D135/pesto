#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-DirectoryDelta60Tests.ps1 : chaque mutation d'une copie hors sac du
# module du repertoire doit faire echouer exactement son controle (exit 1) et la copie temoin doit passer.
# Le delta AD ne parle ici qu'au double local de transport ; les mutations portent sur le branchement
# worker/refresh/releve et sur les gardes du merge et du curseur. La copie se limite au module requis
# par la suite et a la suite elle-meme : cfg.json n'est jamais copie.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-DirectoryDelta60Tests.ps1'
$suiteRelative='tests/Run-DirectoryDelta60Tests.ps1'
$copiedFiles=@('wad/Pesto-Directory.ps1')
$hostExe=(Get-Process -Id $PID).Path
$n=0
function Check($ok,$message){if(-not $ok){throw $message};$script:n++}

function Read-Utf8File{
    param([string]$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset=if($hasBom){3}else{0}
    $text=[Text.Encoding]::UTF8.GetString($bytes,$offset,$bytes.Length-$offset)
    $nl=if($text.Contains("`r`n")){"`r`n"}else{"`n"}
    return [pscustomobject]@{Text=$text;HasBom=$hasBom;Newline=$nl}
}
function Write-Utf8File{
    param([string]$Path,[pscustomobject]$Doc)
    [IO.File]::WriteAllText($Path,$Doc.Text,[Text.UTF8Encoding]::new($Doc.HasBom))
}
function Replace-Once{
    param([pscustomobject]$Doc,[string]$Pattern,[string]$Replacement)
    $found=[regex]::Matches($Doc.Text,$Pattern)
    Check ($found.Count -eq 1) ('Mutation pattern must match exactly once: '+$Pattern)
    $m=$found[0]
    $Doc.Text=$Doc.Text.Substring(0,$m.Index)+$Replacement+$Doc.Text.Substring($m.Index+$m.Length)
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMut60-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try{
        foreach($f in $copiedFiles){
            $destination=Join-Path $temp $f
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            Copy-Item -LiteralPath (Join-Path $root $f) -Destination $destination
        }
        $suiteCopy=Join-Path $temp $suiteRelative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($suiteCopy))
        Copy-Item -LiteralPath $suiteSource -Destination $suiteCopy
        $tree=@(Get-ChildItem -LiteralPath $temp -Recurse -File|ForEach-Object{$_.FullName.Substring($temp.Length+1).Replace('\','/')})
        Check (@(Compare-Object -ReferenceObject ($copiedFiles+$suiteRelative) -DifferenceObject $tree).Count -eq 0) ($Label+': the copy drifted from the whitelist')
        if($Mutation){& $Mutation $temp $suiteCopy}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $output=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $suiteCopy 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE
        $ErrorActionPreference=$previous
        $text=$output -join "`n"
        # Le formateur d'exception PowerShell colore (sequences ANSI) et replie les messages longs :
        # la comparaison est faite sur le texte debarrasse des sequences de couleur et dont les blancs
        # sont reduits, augmentee de la ligne PESTO60-FAIL rendue par la suite elle-meme.
        $marker=@($output|Where-Object{$_ -like 'PESTO60-FAIL:*'}) -join "`n"
        $flat=(((($text+"`n"+$marker)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'DirectoryDelta60 : \d+/\d+ PASS') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

$mutationWorkerIgnoresDelta={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$incremental=Get-PestoIncrementalInventory -Request \$Request -DC \$dc -Maximum \$limit' -Replacement '$incremental=$null'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationRefreshDropsCursor={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$script:PestoDirectorySyncState=\$Snapshot\.SyncState' -Replacement ''
    Write-Utf8File -Path $path -Doc $doc
}
$mutationCredentialKeepsCursor={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(-not \$script:PestoDirectoryAuthScope -or -not \[object\]::ReferenceEquals\(\$script:PestoDirectoryAuthCredential,\$Credential\)\)' -Replacement 'if(-not $script:PestoDirectoryAuthScope)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationStateKeepsOldCookie={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'Cookie=\[byte\[\]\]\$delta\.Cookie' -Replacement 'Cookie=[byte[]]$cookie'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationDeletionIgnored={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$change\.Deleted -eq \$true\)\{\$rows\.Remove\(\$key\);continue\}' -Replacement 'if($change.Deleted -eq $true){continue}'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationCursorIgnoresDC={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$State\.DC -ine \$DC -or ' -Replacement ''
    Write-Utf8File -Path $path -Doc $doc
}
$mutationMoveOutsideScopeRetained={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Directory.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\}else\{\$rows\.Remove\(\$key\)\}' -Replacement '}else{}'
    Write-Utf8File -Path $path -Doc $doc
}

Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'Worker ignores the incremental delta' -Mutation $mutationWorkerIgnoresDelta -ExpectedFailure @('Full scan ran despite incremental delta')
Invoke-Scenario -Label 'Refresh drops the published cursor' -Mutation $mutationRefreshDropsCursor -ExpectedFailure @('Refresh did not persist the published cursor')
Invoke-Scenario -Label 'Credential rotation keeps the authenticated cursor' -Mutation $mutationCredentialKeepsCursor -ExpectedFailure @('Another credential kept the authenticated cursor')
Invoke-Scenario -Label 'Published state keeps the old cookie' -Mutation $mutationStateKeepsOldCookie -ExpectedFailure @('Cookie was not advanced with the rows')
Invoke-Scenario -Label 'Deletion ignored by the merge' -Mutation $mutationDeletionIgnored -ExpectedFailure @('Deletion retained')
Invoke-Scenario -Label 'Cursor ignores the domain controller' -Mutation $mutationCursorIgnoresDC -ExpectedFailure @('Different DC accepted')
Invoke-Scenario -Label 'Move outside scope retained by the merge' -Mutation $mutationMoveOutsideScopeRetained -ExpectedFailure @('Move outside scope retained')
Write-Output "DirectoryDelta60Mutations : $n/$n PASS"

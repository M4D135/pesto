#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-CompiledHelpers63Tests.ps1 : chaque mutation d'une copie hors sac de
# l'arbre livre doit faire echouer exactement son controle (exit 1) et la copie temoin doit passer.
# Chaque scenario joue dans un processus enfant separe (le chargeur met en cache Pesto.Runtime par
# domaine d'application). La copie se limite aux onze fichiers requis par la suite et a la suite elle-meme :
# cfg.json n'est jamais copie.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-CompiledHelpers63Tests.ps1'
$suiteRelative='tests/Run-CompiledHelpers63Tests.ps1'
$copiedFiles=@('wad/Pesto-Common.ps1','wad/Pesto-Operations.ps1','wad/Pesto-Core.ps1','wad/Pesto.Engine.Runtime.ps1','wad/Pesto.Runtime.dll','wad/Pesto-LogWriter.cs','src/Pesto.Runtime/CompactIndex.cs','src/Pesto.Runtime/NativePipe.cs','src/Pesto.Runtime/NativeShell.cs','tools/Build-PestoRuntimeTypes.ps1','tests/Measure-Engine120.ps1')
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
function Split-Lines{
    param([pscustomobject]$Doc)
    $lines=[Collections.Generic.List[string]]::new()
    foreach($line in [regex]::Split($Doc.Text,[regex]::Escape($Doc.Newline))){[void]$lines.Add($line)}
    return ,$lines
}
function Move-GateCallerAfterSecret{
    # Deplace l'appel de la porte du canal eleve apres la lecture du secret, dans une copie donnee
    # (produit livre ou module Engine genere) : la garde de l'ordre doit faire echouer son controle.
    param([string]$Temp,[string]$Relative)
    $path=Join-Path $Temp $Relative
    $doc=Read-Utf8File -Path $path
    $lines=Split-Lines -Doc $doc
    $gate=@(0..($lines.Count-1)|Where-Object{$lines[$_] -match '^\s*\[void\]\(Test-PestoPipeClient -Pipe \$pipe -ExpectedProcessId \$proc\.Id\)\s*$'})
    Check ($gate.Count -eq 1) ('Elevated-channel gate caller not found exactly once for reordering in '+$Relative)
    $gateLine=$lines[$gate[0]]
    [void]$lines.RemoveAt($gate[0])
    $cred=-1;for($i=$gate[0];$i -lt $lines.Count;$i++){if($lines[$i] -match 'GetNetworkCredential\(\)\.Password'){$cred=$i;break}}
    Check ($cred -ge 0) ('Secret read not found after the gate for reordering in '+$Relative)
    $lines.Insert($cred+1,$gateLine)
    $doc.Text=$lines -join $doc.Newline
    Write-Utf8File -Path $path -Doc $doc
}
function Move-IconGuardBeforeTry{
    # Sort le bloc de garde AppUserModelID de l'essai qui l'encadre (produit livre ou module Engine
    # genere) : l'appel natif d'icone devient souple sans try et son controle doit echouer.
    param([string]$Temp,[string]$Relative)
    $path=Join-Path $Temp $Relative
    $doc=Read-Utf8File -Path $path
    $lines=Split-Lines -Doc $doc
    $fn=-1;for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match '^function Set-WindowIcon'){$fn=$i;break}}
    Check ($fn -ge 0) ('Icon function anchor not found in '+$Relative)
    $guard=@(0..($lines.Count-1)|Where-Object{$lines[$_] -match 'if\(-not \$script:PestoAppUserModelIdSet'})
    Check ($guard.Count -eq 1) ('AppUserModelID guard block not found exactly once in '+$Relative)
    $g=$guard[0]
    Check ($lines[$g+1] -match 'SetCurrentProcessExplicitAppUserModelID' -and $lines[$g+2] -match 'PestoAppUserModelIdSet=\$true' -and $lines[$g+3].Trim() -eq '}') ('AppUserModelID guard block shape changed in '+$Relative)
    $try=-1;for($i=$fn;$i -lt $g;$i++){if($lines[$i] -match '^\s*try \{\s*$'){$try=$i;break}}
    Check ($try -ge 0) ('Opening try of the icon path not found before the guard in '+$Relative)
    $block=@($lines[$g..($g+3)])
    $kept=[Collections.Generic.List[string]]::new()
    for($i=0;$i -lt $lines.Count;$i++){
        if($i -eq $try){foreach($b in $block){[void]$kept.Add($b)}}
        if($i -ge $g -and $i -le $g+3){continue}
        [void]$kept.Add($lines[$i])
    }
    $doc.Text=$kept -join $doc.Newline
    Write-Utf8File -Path $path -Doc $doc
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMut63-'+[Guid]::NewGuid().ToString('N'))
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
        # Le formateur d'exception PowerShell colore (sequences ANSI) et replie les messages longs sur
        # plusieurs lignes : la comparaison est faite sur le texte debarrasse des sequences de couleur et
        # dont les blancs sont reduits, augmentee de la ligne PESTO63-FAIL rendue par la suite elle-meme.
        # Le rapport, lui, reste le texte brut.
        $marker=@($output|Where-Object{$_ -like 'PESTO63-FAIL:*'}) -join "`n"
        $flat=(((($text+"`n"+$marker)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'CompiledHelpers63 : \d+/\d+ PASS') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

$mutationNativeDrift={
    param($temp,$suiteCopy)
    $doc=Read-Utf8File -Path $suiteCopy
    Replace-Once -Doc $doc -Pattern 'user32\.dll\|DestroyIcon' -Replacement 'user32x.dll|DestroyIcon'
    Write-Utf8File -Path $suiteCopy -Doc $doc
}
$mutationGateNoThrow={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Operations.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern "\{throw 'Impossible[^']*'\}" -Replacement '{ }'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationGateAfterSecret={
    param($temp,$suiteCopy)
    Move-GateCallerAfterSecret -Temp $temp -Relative 'wad/Pesto-Operations.ps1'
}
$mutationIconUnguarded={
    param($temp,$suiteCopy)
    Move-IconGuardBeforeTry -Temp $temp -Relative 'wad/Pesto-Core.ps1'
}
# Evaluation 63 : les trois mutations du comparateur precompile/Add-Type.
$mutationAuditPayload={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-LogWriter.cs'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'GetBytes\(entry\.Text\)' -Replacement 'GetBytes(entry.Text+''|'')'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationLoaderBypass={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tests/Measure-Engine120.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'Initialize-PestoRuntimeTypes -Root \(Join-Path \$root ''wad''\)' -Replacement '[void][Reflection.Assembly]::LoadFrom((Join-Path $root ''wad/Pesto.Runtime.dll''))'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationMissingSource={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tests/Measure-Engine120.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern "'src/Pesto\.Runtime/NativeShell\.cs'" -Replacement "'src/Pesto.Runtime/NativeShellX.cs'"
    Write-Utf8File -Path $path -Doc $doc
}
# Porte du canal, chargeur verifie et build tool : les sept mutations ajoutees le 23 octobre. Elles portent
# la ou les precedentes ne passaient pas : la seconde copie assertee (module Engine genere), l'appel du
# chargeur dans la porte, la negation de l'appel natif, les gardes anti-falsification du chargeur livre et
# la liste des sources relue chez l'outil de build.
$mutationGateLoaderCallRemoved={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Operations.ps1'
    $doc=Read-Utf8File -Path $path
    $lines=Split-Lines -Doc $doc
    $loader=@(0..($lines.Count-1)|Where-Object{$lines[$_] -match '^\s*Initialize-PestoRuntimeTypes\s*$'})
    Check ($loader.Count -eq 1) 'Loader call inside the pipe gate not found exactly once for removal'
    [void]$lines.RemoveAt($loader[0])
    $doc.Text=$lines -join $doc.Newline
    Write-Utf8File -Path $path -Doc $doc
}
$mutationGateNegationDropped={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Operations.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(-not \[Pesto\.NativePipe17\]::GetNamedPipeClientProcessId' -Replacement 'if([Pesto.NativePipe17]::GetNamedPipeClientProcessId'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationModuleGateNoThrow={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto.Engine.Runtime.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern "\{throw 'Impossible[^']*'\}" -Replacement '{ }'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationModuleGateAfterSecret={
    param($temp,$suiteCopy)
    Move-GateCallerAfterSecret -Temp $temp -Relative 'wad/Pesto.Engine.Runtime.ps1'
}
$mutationModuleIconUnguarded={
    param($temp,$suiteCopy)
    Move-IconGuardBeforeTry -Temp $temp -Relative 'wad/Pesto.Engine.Runtime.ps1'
}
$mutationLoaderTamperGuardsOff={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Common.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\.Hash -ine \$expected\)\{throw' -Replacement '.Hash -ine $expected -and $false){throw'
    Replace-Once -Doc $doc -Pattern '\$known\.Path -ine \$path -or ' -Replacement ''
    Replace-Once -Doc $doc -Pattern ' -or \$loaded\[0\]\.Location -ine \$path' -Replacement ''
    Write-Utf8File -Path $path -Doc $doc
}
$mutationBuildToolSourceDrift={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tools/Build-PestoRuntimeTypes.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern "'src/Pesto\.Runtime/NativePipe\.cs'" -Replacement "'src/Pesto.Runtime/NativePipeX.cs'"
    Write-Utf8File -Path $path -Doc $doc
}
# Le bloc publie par le banc (mode evaluation seule) est lu et asserte par la suite : trois mutations du 23
# octobre, une sur le cout reel du chemin livre et deux sur ce que le rapport publie. Elles portent la ou les
# precedentes ne passaient pas : rien, jusqu'ici, ne consommait le rapport du banc.
$mutationDeliveredPathRecompiles={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tests/Measure-Engine120.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$loaded\.Count -ne 1\)\{throw ''Assembly des helpers precompiles absente\.''\}' -Replacement 'if($loaded.Count -ne 1){throw ''Assembly des helpers precompiles absente.''};foreach($late in $PestoCompiledHelperSources){[void](Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $root $late))))}'
    Write-Utf8File -Path $path -Doc $doc
}
# Un cout relatif fixe franchit le seuil du facteur deux sur toute machine ; x3 pouvait rester sous le seuil.
$mutationPublishedCostInflated={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tests/Measure-Engine120.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'CompiledHelpers=\$compiledPair\.Summary' -Replacement 'CompiledHelpers=@($referenceMedian=[double](@($compiledPair.Summary|Where-Object{$_.Mode -ceq ''AddType''})[0].MedianMs);$compiledPair.Summary|ForEach-Object{if($_.Mode -ceq ''Precompiled''){[pscustomobject]@{Mode=$_.Mode;Samples=$_.Samples;Rows=$_.Rows;MedianMs=$referenceMedian*0.75;P95Ms=[Math]::Max($referenceMedian*0.75,$_.P95Ms);Assemblies=$_.Assemblies;NativeEntries=$_.NativeEntries;Digest=$_.Digest}}else{$_}})'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationPublishedSamplesDropped={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'tests/Measure-Engine120.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'CompiledHelpersSamples=\$compiledPair\.Samples' -Replacement 'CompiledHelpersSamples=@()'
    Write-Utf8File -Path $path -Doc $doc
}

Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'Native-surface drift' -Mutation $mutationNativeDrift -ExpectedFailure @('Native surface drifted from the on-target qualification list')
Invoke-Scenario -Label 'Gate without throw' -Mutation $mutationGateNoThrow -ExpectedFailure @('Native pipe failure no longer throws in wad/Pesto-Operations.ps1')
Invoke-Scenario -Label 'Gate after secret' -Mutation $mutationGateAfterSecret -ExpectedFailure @('Pipe gate no longer precedes the secret in wad/Pesto-Operations.ps1')
Invoke-Scenario -Label 'Icon call outside try' -Mutation $mutationIconUnguarded -ExpectedFailure @('Unguarded native icon call at line ',' in wad/Pesto-Core.ps1')
Invoke-Scenario -Label 'Audit writer payload drift' -Mutation $mutationAuditPayload -ExpectedFailure @('Precompiled helpers and runtime-compiled sources no longer render the same workload')
Invoke-Scenario -Label 'Precompiled side bypasses the verified loader' -Mutation $mutationLoaderBypass -ExpectedFailure @('The precompiled side no longer goes through the verified loader')
Invoke-Scenario -Label 'Add-Type side loses a shipped source' -Mutation $mutationMissingSource -ExpectedFailure @('Shipped helper source missing')
Invoke-Scenario -Label 'Gate loader call removed' -Mutation $mutationGateLoaderCallRemoved -ExpectedFailure @('Pipe gate no longer loads the verified library in wad/Pesto-Operations.ps1')
Invoke-Scenario -Label 'Gate negation dropped' -Mutation $mutationGateNegationDropped -ExpectedFailure @('Native pipe call no longer negated in wad/Pesto-Operations.ps1')
Invoke-Scenario -Label 'Module gate without throw' -Mutation $mutationModuleGateNoThrow -ExpectedFailure @('Native pipe failure no longer throws in module Engine genere')
Invoke-Scenario -Label 'Module gate after secret' -Mutation $mutationModuleGateAfterSecret -ExpectedFailure @('Pipe gate no longer precedes the secret in module Engine genere')
Invoke-Scenario -Label 'Module icon call outside try' -Mutation $mutationModuleIconUnguarded -ExpectedFailure @('Unguarded native icon call at line ',' in module Engine genere')
Invoke-Scenario -Label 'Verified loader tamper guards off' -Mutation $mutationLoaderTamperGuardsOff -ExpectedFailure @('Tampered DLL accepted')
Invoke-Scenario -Label 'Build tool source list drift' -Mutation $mutationBuildToolSourceDrift -ExpectedFailure @('The Add-Type side no longer compiles the four sources the build tool compiles')
Invoke-Scenario -Label 'Delivered path recompiles at runtime' -Mutation $mutationDeliveredPathRecompiles -ExpectedFailure @('The delivered path is no longer cheaper than cold Add-Type compilation')
Invoke-Scenario -Label 'Published precompiled cost inflated' -Mutation $mutationPublishedCostInflated -ExpectedFailure @('The evaluation result no longer holds: the verified loader is not at least twice as cheap as cold Add-Type')
Invoke-Scenario -Label 'Published block loses its samples' -Mutation $mutationPublishedSamplesDropped -ExpectedFailure @('The published block no longer reports the six played samples')
Write-Output "CompiledHelpers63Mutations : $n/$n PASS"

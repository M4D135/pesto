#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-ManagedExtensionsTests.ps1 pour le point 111 : chaque mutation d'une copie
# hors sac des modules du moteur doit faire echouer exactement le controle de son garde (exit 1) et la copie
# temoin doit passer. Les gardes frappees sont les trois classes de champs du scénario administre
# (obligatoires, autorises, verrouilles), l'identite des facettes, l'ecrasement GPO, le branchement du
# controle avant effets et le branchement du controle avant effets. Aucune copie de cfg.json, aucun
# appel AD, Windows ou VM : le scénario ne parle qu'au validateur local du moteur.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-ManagedExtensionsTests.ps1'
$suiteRelative='tests/Run-ManagedExtensionsTests.ps1'
$copiedFiles=@('wad/Pesto-Contracts.ps1','wad/Pesto-Configuration.ps1','wad/Pesto-ManagedPolicy.ps1','wad/Pesto-Policy.ps1','wad/Pesto-Enterprise.ps1')
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMut111-'+[Guid]::NewGuid().ToString('N'))
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
        # sont reduits, augmentee des lignes FAIL rendues par la suite elle-meme.
        $marker=@($output|Where-Object{$_ -like 'FAIL *'}) -join "`n"
        $flat=(((($text+"`n"+$marker)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'ManagedExtensions: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

$policy={param($temp) Join-Path $temp 'wad/Pesto-Policy.ps1'}
$managed={param($temp) Join-Path $temp 'wad/Pesto-ManagedPolicy.ps1'}

$mutationRequiredGuardOff={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$field -cin @\(\$s\.Required\) -and -not \$value\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationAllowedGuardOff={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$s\.Allowed\.PSObject\.Properties\[\$field\] -and \$value -cnotin @\(\$s\.Allowed\.\$field\)\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationLockedGuardOff={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$s\.Locked\.PSObject\.Properties\[\$field\] -and \$value -cne \$s\.Locked\.\$field\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationAllowedCaseInsensitive={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$value -cnotin @\(\$s\.Allowed\.\$field\)' -Replacement '$value -notin @($s.Allowed.$field)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationLockedCaseInsensitive={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$value -cne \$s\.Locked\.\$field' -Replacement '$value -ne $s.Locked.$field'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationLockOutsideAllowedAccepted={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$Value\.Allowed\.PSObject\.Properties\[\$p\.Name\] -and \$p\.Value -cnotin @\(\$Value\.Allowed\.\(\$p\.Name\)\)\)' -Replacement 'if($false)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationFacetsReadTheCurrentName={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'ConvertTo-PestoNameParts \(\[string\]\$Plan\.Nouveau_Nom\)' -Replacement 'ConvertTo-PestoNameParts ([string]$Plan.Nom_du_PC)'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationManagedScenarioIgnored={
    param($temp,$suiteCopy)
    $path=& $managed $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'if\(\$v\.PSObject\.Properties\[''Scenario''\]\)\{\$copy\[''Scenario''\]=ConvertTo-PestoScenario \$v\.Scenario\}' -Replacement "if(`$false){`$copy['Scenario']=ConvertTo-PestoScenario `$v.Scenario}"
    Write-Utf8File -Path $path -Doc $doc
}
$mutationEffectGateNotWired={
    param($temp,$suiteCopy)
    $path=& $policy $temp;$doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern 'Assert-PestoScenarioValues \$p\.Scenario \(Get-PestoPlanScenarioValues \$Plan\)' -Replacement 'Write-Verbose ''scenario skipped'''
    Write-Utf8File -Path $path -Doc $doc
}

Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'Required-field guard disabled' -Mutation $mutationRequiredGuardOff -ExpectedFailure @('FAIL Required field with no allowed list is still required')
Invoke-Scenario -Label 'Allowed-values guard disabled' -Mutation $mutationAllowedGuardOff -ExpectedFailure @('FAIL Disallowed type')
Invoke-Scenario -Label 'Locked-field guard disabled' -Mutation $mutationLockedGuardOff -ExpectedFailure @('FAIL Locked field changed')
Invoke-Scenario -Label 'Allowed list compared case-insensitively' -Mutation $mutationAllowedCaseInsensitive -ExpectedFailure @('FAIL Allowed list is case-sensitive')
Invoke-Scenario -Label 'Locked value compared case-insensitively' -Mutation $mutationLockedCaseInsensitive -ExpectedFailure @('FAIL Locked value is case-sensitive')
Invoke-Scenario -Label 'Lock outside the allowed list accepted' -Mutation $mutationLockOutsideAllowedAccepted -ExpectedFailure @('FAIL Contradictory rule refused')
Invoke-Scenario -Label 'Facets read the current name instead of the requested one' -Mutation $mutationFacetsReadTheCurrentName -ExpectedFailure @('FAIL Engine derives fields from actual name')
Invoke-Scenario -Label 'Managed scenario no longer overrides the local one' -Mutation $mutationManagedScenarioIgnored -ExpectedFailure @('FAIL GPO scenario overrides local')
Invoke-Scenario -Label 'Scenario no longer asserted before the effects' -Mutation $mutationEffectGateNotWired -ExpectedFailure @('FAIL Operation policy gate applies the scenario before any effect')
Write-Output "ManagedScenario111Mutations : $n/$n PASS"

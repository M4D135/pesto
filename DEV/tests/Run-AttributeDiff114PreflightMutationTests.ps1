#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-AttributeDiff114PreflightTests.ps1 (evaluation du diff attributs, point 114) :
# chaque mutation d'une copie hors sac du consommateur integrateur ou de l'apercu qu'il doit confronter au moteur
# doit faire echouer exactement le cas de la garde visee (exit non nul) et la copie temoin doit passer. Sont
# frappees ici les gardes propres au controle avant remise : confrontation des deux jambes, garde du moteur
# appliquee aux lignes de l'apercu, comparaison ligne a ligne, fermeture du texte des refus (aucun contenu
# candidat ne sort), refus des membres homonymes, taille des documents, integrity du paquet, identite de l'objet,
# jamais de remplacement silencieux du rapport, code de sortie coherent, et les gardes de l'apercu qui n'ont pas
# d'equivalent dans le moteur. Les transports AD, la plateforme et les magasins restent des doubles locaux :
# aucun appel reseau, aucune VM, aucune ecriture hors du sac detruit.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-AttributeDiff114PreflightTests.ps1'
$suiteRelative='tests/Run-AttributeDiff114PreflightTests.ps1'
$copiedFiles=@('wad/Pesto-Contracts.ps1','wad/Pesto-Extensions.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoAttributeDiff.ps1')
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
    param([pscustomobject]$Doc,[string]$Literal,[string]$Replacement)
    $found=@([regex]::Matches($Doc.Text,[regex]::Escape($Literal)))
    Check ($found.Count -eq 1) ('Mutation pattern must match exactly once: '+$Literal)
    $m=$found[0]
    $Doc.Text=$Doc.Text.Substring(0,$m.Index)+$Replacement+$Doc.Text.Substring($m.Index+$m.Length)
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutDiff114-'+[Guid]::NewGuid().ToString('N'))
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
        if($Mutation){& $Mutation $temp}
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        Push-Location $temp
        try{
            $output=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $suiteCopy 2>&1|ForEach-Object{[string]$_})
            $code=$LASTEXITCODE
        }finally{Pop-Location}
        $ErrorActionPreference=$previous
        $text=$output -join "`n"
        $flat=(((($text)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'AttributeDiff114Preflight: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}
function Mutate-Consumer{
    param([string]$Temp,[string[]]$Pairs)
    $path=Join-Path $Temp 'integrations/Test-PestoAttributeDiff.ps1'
    $doc=Read-Utf8File -Path $path
    for($i=0;$i -lt $Pairs.Count;$i+=2){Replace-Once -Doc $doc -Literal ($Pairs[$i] -replace '\{NL\}',$doc.Newline) -Replacement ($Pairs[$i+1] -replace '\{NL\}',$doc.Newline)}
    Write-Utf8File -Path $path -Doc $doc
}
function Mutate-Module{
    param([string]$Temp,[string[]]$Pairs)
    $path=Join-Path $Temp 'integrations/Pesto.Optional.psm1'
    $doc=Read-Utf8File -Path $path
    for($i=0;$i -lt $Pairs.Count;$i+=2){Replace-Once -Doc $doc -Literal ($Pairs[$i] -replace '\{NL\}',$doc.Newline) -Replacement ($Pairs[$i+1] -replace '\{NL\}',$doc.Newline)}
    Write-Utf8File -Path $path -Doc $doc
}

Invoke-Scenario -Label 'Witness' -Mutation $null

Invoke-Scenario -Label 'Both legs no longer confronted' -ExpectedFailure @('A preview that drops the reference field is refused as divergent') -Mutation {param($t);Mutate-Consumer $t @('$report[''Divergence'']=(-not $report[''DiffMatches'']) -or ($previewRefusal -cne $engineRefusal)','$report[''Divergence'']=$false')}
Invoke-Scenario -Label 'Engine guard no longer judges the engine rows' -ExpectedFailure @('A preview that no longer counts changes is caught by the engine guard') -Mutation {param($t);Mutate-Consumer $t @('try{[void](Assert-PestoAttributeChanges $engineRows)}catch{$engineRefusal=[string]$_.Exception.Message}','try{[void]($engineRows)}catch{$engineRefusal=[string]$_.Exception.Message}')}
Invoke-Scenario -Label 'Engine guard no longer judges the preview rows' -ExpectedFailure @('A preview that drops the reference field is refused as divergent') -Mutation {param($t);Mutate-Consumer $t @('try{[void](Assert-PestoAttributeChanges $previewRows)}catch{$previewRefusal=[string]$_.Exception.Message}','try{[void]($previewRows)}catch{$previewRefusal=[string]$_.Exception.Message}')}
Invoke-Scenario -Label 'Row by row comparison no longer performed' -ExpectedFailure @('A preview that rewrites the value it claims to replace is refused as divergent') -Mutation {param($t);Mutate-Consumer $t @('$report[''DiffMatches'']=((Get-PestoAttributeRowKey $previewRows) -ceq (Get-PestoAttributeRowKey $engineRows))','$report[''DiffMatches'']=$true')}
Invoke-Scenario -Label 'Refusals no longer closed before leaving the control' -ExpectedFailure @('An attribute outside the three allowed is refused without echoing its name') -Mutation {param($t);Mutate-Consumer $t @('    if($Text -cin $closed){return $Text}','    return $Text')}
Invoke-Scenario -Label 'Duplicated members no longer refused on the text' -ExpectedFailure @('A duplicated member in the request document is refused on the text') -Mutation {param($t);Mutate-Consumer $t @('    if((@(Get-PestoJsonMemberNames $text|Group-Object -CaseSensitive|Where-Object{$_.Count -gt 1})).Count){throw ''Document candidat illisible.''}','')}
Invoke-Scenario -Label 'Oversized candidate document accepted' -ExpectedFailure @('An oversized candidate document is refused') -Mutation {param($t);Mutate-Consumer $t @('if($raw.Length -lt 1 -or $raw.Length -gt 65536){','if($false){')}
Invoke-Scenario -Label 'Package integrity no longer required' -ExpectedFailure @('An unverified package is refused before any evaluation') -Mutation {param($t);Mutate-Consumer $t @('if(-not(Test-PestoPackage -Root $Installation)){','if($false){')}
Invoke-Scenario -Label 'Object identity no longer validated' -ExpectedFailure @('A missing or malformed object identity is refused') -Mutation {param($t);Mutate-Consumer $t @('if(-not[Guid]::TryParse($ObjectGuid,[ref]$guid) -or $guid -eq [Guid]::Empty){','if($false){')}
Invoke-Scenario -Label 'Handed-over report silently overwritten' -ExpectedFailure @('The report is never silently overwritten') -Mutation {param($t);Mutate-Consumer $t @('$stream=[IO.File]::Open([IO.Path]::GetFullPath($ReportPath),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)','$stream=[IO.File]::Open([IO.Path]::GetFullPath($ReportPath),[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)')}
Invoke-Scenario -Label 'Exit code no longer follows the verdict' -ExpectedFailure @('A request equal to the current state is refused before the handover','A managedBy value without a distinguished name is refused by both legs') -Mutation {param($t);Mutate-Consumer $t @('$report[''ExitCode'']=if($report[''Executable'']){0}else{96}','$report[''ExitCode'']=0')}
Invoke-Scenario -Label 'Preview whitelist widened' -ExpectedFailure @('An attribute outside the three allowed is refused without echoing its name') -Mutation {param($t);Mutate-Module $t @('if($property.Name -cnotin @(''description'',''location'',''managedBy'')){','if($property.Name -cnotin @(''description'',''location'',''managedBy'',''CANARY114userAccountControl'',''distinguishedName'',''userPassword'')){')}
Invoke-Scenario -Label 'Preview no longer requires a distinguished name' -ExpectedFailure @('A managedBy value without a distinguished name is refused by both legs') -Mutation {param($t);Mutate-Module $t @('if($property.Name -eq ''managedBy'' -and $property.Value -and $property.Value -notmatch ''^(CN|OU)=.+,DC=''){','if($false){')}
Invoke-Scenario -Label 'Preview no longer counts changes' -ExpectedFailure @('A request equal to the current state is refused before the handover') -Mutation {param($t);Mutate-Module $t @('if($changes.Count -lt 1 -or $changes.Count -gt 3){','if($false){')}
Invoke-Scenario -Label 'Preview rows no longer carry the reference field' -ExpectedFailure @('A preview that drops the reference field is refused as divergent') -Mutation {param($t);Mutate-Module $t @('After=$property.Value;ReferenceGuid=''''','After=$property.Value')}

Write-Output "AttributeDiff114PreflightMutations : $n/$n PASS"

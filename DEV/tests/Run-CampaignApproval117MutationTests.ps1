#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-CampaignApproval117Tests.ps1 : chaque mutation d'une copie hors sac de
# wad/Pesto-Policy.ps1, ou du mesureur de taille de cle de la suite, doit faire echouer exactement son
# controle (exit 1) pendant que la copie temoin passe. L'approbation de campagne (point 117) ne parle ici
# qu'aux fournisseurs crypto de l'hote, sur des certificats de fixture auto-signes : aucun appel AD,
# domaine, VM ni reseau. La copie se limite aux cinq modules que la suite point-source et a la suite
# elle-meme : cfg.json n'est jamais copie, et l'original scelle n'est jamais touche.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-CampaignApproval117Tests.ps1'
$suiteRelative='tests/Run-CampaignApproval117Tests.ps1'
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMut117-'+[Guid]::NewGuid().ToString('N'))
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
        $flat=(((($text) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' '))
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'CampaignApproval117: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
        return $flat
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

# Les deux premieres mutations attaquent la garde de taille de cle du produit, une par jambe. Les motifs
# sont entre simples quotes : ni apostrophe ni dollar ne sont developpes, et Replace-Once exige une
# occurrence unique, ce qui garantit que chaque mutation ne touche que la jambe visee.
$mutationSigningGuardDropsSize={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Policy.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern '\$key\.KeySize -lt 2048\)\{throw' -Replacement '$false){throw'
    Write-Utf8File -Path $path -Doc $doc
}
$mutationVerifyingGuardDropsSize={
    param($temp,$suiteCopy)
    $path=Join-Path $temp 'wad/Pesto-Policy.ps1'
    $doc=Read-Utf8File -Path $path
    Replace-Once -Doc $doc -Pattern ' -or \$key\.KeySize -lt 2048 -or' -Replacement ' -or'
    Write-Utf8File -Path $path -Doc $doc
}
# Les deux suivantes attaquent le mesureur de la suite elle-meme : un mesureur fige, en haut comme en bas,
# doit etre tue, sinon l'adaptateur de fixture ne serait qu'un tampon et les accords faibles passeraient.
$mutationMeasurementFrozenHigh={
    param($temp,$suiteCopy)
    $doc=Read-Utf8File -Path $suiteCopy
    Replace-Once -Doc $doc -Pattern '\[int\]\(\$this\.ExportParameters\(\$false\)\.Modulus\.Length\*8\)' -Replacement '2048'
    Write-Utf8File -Path $suiteCopy -Doc $doc
}
$mutationMeasurementFrozenLow={
    param($temp,$suiteCopy)
    $doc=Read-Utf8File -Path $suiteCopy
    Replace-Once -Doc $doc -Pattern '\[int\]\(\$this\.ExportParameters\(\$false\)\.Modulus\.Length\*8\)' -Replacement '0'
    Write-Utf8File -Path $suiteCopy -Doc $doc
}

$witness=Invoke-Scenario -Label 'Witness' -Mutation $null
$adapted=$witness.Contains('key size measured by fixture modulus')
Invoke-Scenario -Label 'Signing leg accepts an undersized approver key' -Mutation $mutationSigningGuardDropsSize -ExpectedFailure @('FAIL Weak approver key refused by the rule, not by a binding error') | Out-Null
Invoke-Scenario -Label 'Verifying leg accepts an undersized approver key' -Mutation $mutationVerifyingGuardDropsSize -ExpectedFailure @('FAIL Weak approver key refused by the rule, not by a binding error') | Out-Null
if($adapted){
    Invoke-Scenario -Label 'Fixture measurement frozen at the floor' -Mutation $mutationMeasurementFrozenHigh -ExpectedFailure @('FAIL Key size is measured from the modulus, never frozen','FAIL Weak approver key refused by the rule, not by a binding error') | Out-Null
    # Un mesureur fige sous le plancher ne peut pas etre un mesureur : la jambe de signature du produit refuse
    # alors un approbateur legitime de 2048 bits, et la suite s'arrete la-dessus au lieu de passer.
    Invoke-Scenario -Label 'Fixture measurement frozen below the floor' -Mutation $mutationMeasurementFrozenLow -ExpectedFailure @('Cle privee RSA 2048 bits minimum requise.') | Out-Null
}else{
    Write-Host 'NOTE: hote mesurant KeySize nativement, les deux mutations du mesureur de fixture sont sans effet et ne sont pas jouees.'
}
Write-Output "CampaignApproval117Mutations : $n/$n PASS"

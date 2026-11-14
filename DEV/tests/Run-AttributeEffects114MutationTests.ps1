#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-ExtensionEffectsTests.ps1 (extension attributs, point 114) : chaque
# mutation d'une copie hors sac du moteur doit faire echouer exactement le controle de sa garde (exit 1)
# et la copie temoin doit passer. Les gardes frappees sont celles du diff (forme, vide, duplique,
# reference managedBy), de la cible (GUID, perimetre OU, domaine), du plan (integrite, expiration,
# empreinte de configuration, machine, domaine), de l'execution (valeur avant, cible deplacee, reference
# remplacee, relecture apres ecriture, politique moteur, approbation de campagne, ordre de persistance)
# et du recu (intention, domaine, session en lecture seule, non-rejeu). L'AD, DPAPI et djoin restent des
# doubles locaux : aucun appel reseau, aucune VM. La copie se limite au moteur requis par la suite et a
# la suite elle-meme : cfg.json n'est jamais copie.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-ExtensionEffectsTests.ps1'
$suiteRelative='tests/Run-ExtensionEffectsTests.ps1'
$copiedFiles=@('wad/Pesto.Engine.Runtime.ps1')
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
    $found=[regex]::Matches($Doc.Text,[regex]::Escape($Literal))
    Check ($found.Count -eq 1) ('Mutation pattern must match exactly once: '+$Literal)
    $m=$found[0]
    $Doc.Text=$Doc.Text.Substring(0,$m.Index)+$Replacement+$Doc.Text.Substring($m.Index+$m.Length)
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMut114-'+[Guid]::NewGuid().ToString('N'))
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
        $flat=(((($text)) -replace '\x1b\[[0-9;]*[A-Za-z]','') -replace '\s+',' ')
        if($null -eq $ExpectedFailure){
            Check ($code -eq 0) ($Label+': witness suite exited '+$code+' : '+$text)
            Check ($flat -match 'ExtensionEffects: \d+ passed, 0 failed') ($Label+': witness summary line missing')
        }else{
            Check ($code -ne 0) ($Label+': mutated suite unexpectedly passed')
            foreach($needle in $ExpectedFailure){Check ($flat.Contains($needle)) ($Label+': expected failure message missing: '+$needle+' ; got : '+$text)}
        }
    }finally{Remove-Item -LiteralPath $temp -Recurse -Force}
}

function Mutate-Runtime{
    param([string]$Temp,[string[]]$Pairs)
    $path=Join-Path $Temp 'wad/Pesto.Engine.Runtime.ps1'
    $doc=Read-Utf8File -Path $path
    for($i=0;$i -lt $Pairs.Count;$i+=2){Replace-Once -Doc $doc -Literal ($Pairs[$i] -replace '\{NL\}',$doc.Newline) -Replacement ($Pairs[$i+1] -replace '\{NL\}',$doc.Newline)}
    Write-Utf8File -Path $path -Doc $doc
}

$policyLiteral='Changes=$Plan.Changes}{NL}        Assert-PestoOperationPolicy $effect $script:PestoPolicy'

Invoke-Scenario -Label 'Witness' -Mutation $null
Invoke-Scenario -Label 'Attribute value validation removed' -ExpectedFailure @('Non-string attribute value refused') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$p.Value -isnot [string] -or `$p.Value.Length -gt 1024 -or `$p.Value -match '[\x00-\x1f\x7f]'){throw 'Valeur attribut invalide.'}","if(`$false){throw 'Valeur attribut invalide.'}")}
Invoke-Scenario -Label 'managedBy DN shape guard removed' -ExpectedFailure @('managedBy without a distinguished name refused') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$p.Name -eq 'managedBy' -and `$p.Value -and `$p.Value -notmatch '^(CN|OU)=.+,DC='){throw 'managedBy exige un DN.'}","if(`$false){throw 'managedBy exige un DN.'}")}
Invoke-Scenario -Label 'Diff inverted against the current value' -ExpectedFailure @('Preview has exact diff and makes no mutation') -Mutation {param($t,$s);Mutate-Runtime $t @('if([string]$Current.($p.Name) -cne $p.Value){','if([string]$Current.($p.Name) -ceq $p.Value){')}
Invoke-Scenario -Label 'Empty change list accepted' -ExpectedFailure @('No-op request produces no plan and no write') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$Changes -is [string] -or @(`$Changes).Count -lt 1 -or @(`$Changes).Count -gt 3","if(`$Changes -is [string] -or @(`$Changes).Count -gt 3")}
Invoke-Scenario -Label 'Empty diff accepted' -ExpectedFailure @('Empty diff refused by the diff guard') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$c.Before -ceq `$c.After){throw 'Diff vide.'}","if(`$false){throw 'Diff vide.'}")}
Invoke-Scenario -Label 'Duplicate attribute accepted' -ExpectedFailure @('Duplicate attribute refused by the diff guard') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$c.Attribute -cnotin @('description','location','managedBy') -or `$seen.ContainsKey(`$c.Attribute))","if(`$c.Attribute -cnotin @('description','location','managedBy'))")}
Invoke-Scenario -Label 'Diff sides left unvalidated' -ExpectedFailure @('Control character in a diff side refused') -Mutation {param($t,$s);Mutate-Runtime $t @("foreach(`$field in @('Before','After')){if(`$c.`$field -isnot [string] -or `$c.`$field.Length -gt 1024 -or `$c.`$field -match '[\x00-\x1f\x7f]'){throw 'Diff attribut invalide.'}}","foreach(`$field in @('Before','After')){if(`$false){throw 'Diff attribut invalide.'}}")}
Invoke-Scenario -Label 'managedBy reference identity not required' -ExpectedFailure @('managedBy without reference identity refused') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$c.Attribute -eq 'managedBy' -and `$c.After){`$g=[Guid]::Empty;if(-not[Guid]::TryParse([string]`$c.ReferenceGuid,[ref]`$g) -or `$g -eq [Guid]::Empty){throw 'Identite managedBy manquante.'}}","if(`$c.Attribute -eq 'managedBy' -and `$c.After){}")}
Invoke-Scenario -Label 'Unexpected reference accepted' -ExpectedFailure @('Reference pinned only for managedBy') -Mutation {param($t,$s);Mutate-Runtime $t @("elseif(`$c.ReferenceGuid){throw 'Reference inattendue.'}","elseif(`$false){throw 'Reference inattendue.'}")}
Invoke-Scenario -Label 'Target OU scope ignored' -ExpectedFailure @('Target outside the configured OU scope refused') -Mutation {param($t,$s);Mutate-Runtime $t @('-not(Test-PestoOUInConfiguredScope (Get-PestoParentDN $pc.DistinguishedName)) -or ','')}
Invoke-Scenario -Label 'Target domain ignored' -ExpectedFailure @('Target in a configured OU of another domain refused') -Mutation {param($t,$s);Mutate-Runtime $t @('(Get-PestoDomainFromDN $pc.DistinguishedName) -ine $script:DOMAINE','(Get-PestoDomainFromDN $pc.DistinguishedName) -ine $script:DOMAINE -and $false')}
Invoke-Scenario -Label 'Target GUID not compared' -ExpectedFailure @('Target GUID returned by AD does not match the request') -Mutation {param($t,$s);Mutate-Runtime $t @('[Guid]$pc.ObjectGUID -ne $ObjectGuid -or ','')}
Invoke-Scenario -Label 'Plan integrity checksum ignored' -ExpectedFailure @('Tampered diff rejected even with unchanged plan checksum') -Mutation {param($t,$s);Mutate-Runtime $t @('(Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -cne $Plan.Integrity -or ','')}
Invoke-Scenario -Label 'Plan expiry ignored' -ExpectedFailure @('Expired plan refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @('$expires -le [DateTimeOffset]::UtcNow -or $expires -le $created -or ($expires-$created).TotalHours -gt 24.1 -or $Plan.ConfigStamp','$expires -le $created -or ($expires-$created).TotalHours -gt 24.1 -or $Plan.ConfigStamp')}
Invoke-Scenario -Label 'Plan configuration stamp ignored' -ExpectedFailure @('Plan from another configuration signature refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @('$Plan.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or ','')}
Invoke-Scenario -Label 'Plan machine identity ignored' -ExpectedFailure @('Plan prepared on another machine refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @('$Plan.MachineId -cne (Get-PestoAutomationMachineId) -or ','')}
Invoke-Scenario -Label 'Plan domain ignored' -ExpectedFailure @('Plan for another domain refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @('-or $Plan.Domain -ine $script:DOMAINE','')}
Invoke-Scenario -Label 'Stale before value accepted' -ExpectedFailure @('Stale before value refuses mutation') -Mutation {param($t,$s);Mutate-Runtime $t @("if([string]`$pc.(`$c.Attribute) -cne `$c.Before){throw 'Un attribut a change depuis la preparation.'}","if(`$false){throw 'Un attribut a change depuis la preparation.'}")}
Invoke-Scenario -Label 'Moved or renamed target accepted' -ExpectedFailure @('Target moved after preparation refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$pc.Name -ine `$Plan.Computer -or (Get-PestoParentDN `$pc.DistinguishedName) -ine `$Plan.SourceOU){throw 'Cible deplacee ou renommee depuis preparation.'}","if(`$false){throw 'Cible deplacee ou renommee depuis preparation.'}")}
Invoke-Scenario -Label 'Replaced managedBy reference accepted' -ExpectedFailure @('Reference moved between plan and execution refuses the write') -Mutation {param($t,$s);Mutate-Runtime $t @("if(-not `$ref -or `$ref.DistinguishedName -ine `$c.After){throw 'Reference managedBy remplacee ou deplacee.'}","if(`$false){throw 'Reference managedBy remplacee ou deplacee.'}")}
Invoke-Scenario -Label 'Read-back after write skipped' -ExpectedFailure @('Write not visible on read-back stays uncertain and is never replayed') -Mutation {param($t,$s);Mutate-Runtime $t @("if([string]`$after.(`$c.Attribute) -cne `$c.After){throw 'Observation apres mutation incomplete.'}","if(`$false){throw 'Observation apres mutation incomplete.'}")}
Invoke-Scenario -Label 'Engine policy no longer consulted' -ExpectedFailure @('Incident mode suspends the attribute write before AD') -Mutation {param($t,$s);Mutate-Runtime $t @($policyLiteral,'Changes=$Plan.Changes}')}
Invoke-Scenario -Label 'Campaign approval skipped' -ExpectedFailure @('Campaign-tagged attribute plan requires an approval') -Mutation {param($t,$s);Mutate-Runtime $t @('Assert-PestoCampaignApproval $effect $Approval','')}
Invoke-Scenario -Label 'AD write allowed before the receipt is persisted' -ExpectedFailure @('Effect persistence failure blocks the AD write') -Mutation {param($t,$s);Mutate-Runtime $t @('Set-PestoEffect -Name Attributes -Value Requested','$started=$true;Set-PestoEffect -Name Attributes -Value Requested')}
Invoke-Scenario -Label 'Read-only session confirms the receipt' -ExpectedFailure @('Read-only observation never confirms the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$matched -and `$env:PESTO_READONLY_SESSION -ne '1')","if(`$matched)")}
Invoke-Scenario -Label 'Receipt without attribute intention observed' -ExpectedFailure @('Observation refuses a receipt without an attribute intention') -Mutation {param($t,$s);Mutate-Runtime $t @("`$receipt.Attributes -notin @('Requested','Confirmed')",'$false')}
Invoke-Scenario -Label 'Foreign receipt domain observed' -ExpectedFailure @('Observation refuses a receipt from another domain') -Mutation {param($t,$s);Mutate-Runtime $t @('$receipt.Plan.Domain -ine $script:DOMAINE -or ','')}
Invoke-Scenario -Label 'Observation advertises a replay' -ExpectedFailure @('Observation never repeats a Set-ADObject') -Mutation {param($t,$s);Mutate-Runtime $t @('Changes=$rows;TargetReadOnly=$true;ReplayAllowed=$false','Changes=$rows;TargetReadOnly=$true;ReplayAllowed=$true')}

Invoke-Scenario -Label 'Requested attribute whitelist widened' -ExpectedFailure @('Unknown AD attribute rejected') -Mutation {param($t,$s);Mutate-Runtime $t @("Assert-PestoClosedObject `$Requested @('description','location','managedBy') @()","Assert-PestoClosedObject `$Requested @('description','location','managedBy','userAccountControl','distinguishedName','userPassword') @()")}
Invoke-Scenario -Label 'Row attribute whitelist widened' -ExpectedFailure @('Attribute outside the three allowed refused by the row guard') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$c.Attribute -cnotin @('description','location','managedBy') -or `$seen.ContainsKey(`$c.Attribute)){throw 'Attribut inconnu ou duplique.'}","if(`$c.Attribute -cnotin @('description','location','managedBy','userAccountControl','userPassword') -or `$seen.ContainsKey(`$c.Attribute)){throw 'Attribut inconnu ou duplique.'}")}
Invoke-Scenario -Label 'Replacement sent as a clear' -ExpectedFailure @('Replace and clear sent once, then observed') -Mutation {param($t,$s);Mutate-Runtime $t @("if(`$c.After){`$replace[`$c.Attribute]=`$c.After}else{`$clear+=@(`$c.Attribute)}","if(`$false){`$replace[`$c.Attribute]=`$c.After}else{`$clear+=@(`$c.Attribute)}")}
Invoke-Scenario -Label 'Observation no longer compares the expected values' -ExpectedFailure @('Divergent observation returns a nonzero code without mutation') -Mutation {param($t,$s);Mutate-Runtime $t @('$matched=(@($rows|Where-Object{-not $_.Matches}).Count -eq 0 -and ','$matched=(')}

Write-Output "AttributeEffects114Mutations : $n/$n PASS"

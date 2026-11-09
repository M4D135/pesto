#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-AttributeEntry114Tests.ps1 (point d'entree public de l'extension attributs,
# point 114) : chaque mutation d'une copie hors sac du moteur doit faire echouer exactement le controle de la
# garde visee (exit 1) et la copie temoin doit passer. Sont frappees ici les gardes propres au point d'entree
# et a ses consommateurs immediats : resolution du cfg par defaut, « plan ou changements directs », exigence
# PlanPath + IdempotencyKey sans export simultane, acheminement vers le registre idempotent, cle idempotente
# (grammaire, empreinte de charge, machine, rejeu, marqueur Replayed, ordre de persistance), gates du contexte
# headless (drapeaux DEBUG, politique, poste hors domaine, credential, controleur decouvert, session en
# consultation) et aller-retour du plan sur disque (chemin absolu, taille, CreateNew, dates normalisees). La
# session en consultation est frappee en paire : seule, l'autre jambe masquerait la mutation. L'AD, la
# plateforme, les ACL et les magasins restent des doubles locaux : aucun appel reseau, aucune VM, aucun
# cfg.json operationnel lu. La copie se limite au moteur requis par la suite, au modele neutre de
# configuration et a la suite elle-meme.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-AttributeEntry114Tests.ps1'
$suiteRelative='tests/Run-AttributeEntry114Tests.ps1'
$copiedFiles=@('wad/Pesto.Engine.Runtime.ps1','tools/cfg.modele-complet.json')
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutEntry114-'+[Guid]::NewGuid().ToString('N'))
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
        # L'enfant s'etablit dans la copie : un mutant qui accepte un chemin relatif ecrirait son plan
        # dans le repertoire courant, donc cette fuite doit rester dans le sac detruit, jamais dans le depot.
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
            Check ($flat -match 'AttributeEntry114: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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

Invoke-Scenario -Label 'Witness' -Mutation $null

Invoke-Scenario -Label 'Default configuration beside the runtime no longer resolved' -ExpectedFailure @('The configuration beside the runtime is used when -ConfigPath is omitted') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $owned){throw ''Une mutation Pesto est deja en cours.''}{NL}        if(-not $ConfigPath){$ConfigPath=Join-Path $RuntimeRoot ''cfg.json''}','if(-not $owned){throw ''Une mutation Pesto est deja en cours.''}{NL}        if($false){$ConfigPath=Join-Path $RuntimeRoot ''cfg.json''}')}
Invoke-Scenario -Label 'Plan file and direct changes accepted together' -ExpectedFailure @('A plan file and direct changes cannot be combined') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Attributes -or $ObjectGuid -ne [Guid]::Empty){throw ''Ne pas combiner plan et changements directs.''','if($false){throw ''Ne pas combiner plan et changements directs.''')}
Invoke-Scenario -Label 'Preview no longer writes the handover plan' -ExpectedFailure @('Preview writes the plan file the operator is told to hand over') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $Execute){if($OutPlanPath){Export-PestoPortablePlan $plan $OutPlanPath}','if(-not $Execute){if($false){Export-PestoPortablePlan $plan $OutPlanPath}')}
Invoke-Scenario -Label 'Execute argument guard removed' -ExpectedFailure @('Execute without a plan file is refused','Execute cannot export a plan at the same time','Execute without an idempotency key is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $PlanPath -or $OutPlanPath -or -not $IdempotencyKey){','if($false){')}
Invoke-Scenario -Label 'Execute accepts a missing plan file' -ExpectedFailure @('Execute without a plan file is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('-not $PlanPath -or $OutPlanPath','$false -or $OutPlanPath')}
Invoke-Scenario -Label 'Execute accepts a simultaneous plan export' -ExpectedFailure @('Execute cannot export a plan at the same time') -Mutation {param($t,$s);Mutate-Runtime $t @('$OutPlanPath -or -not $IdempotencyKey','$false -or -not $IdempotencyKey')}
Invoke-Scenario -Label 'Execute accepts a missing idempotency key' -ExpectedFailure @('Execute without an idempotency key is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('-or -not $IdempotencyKey){throw ''Execution attributs','-or $false){throw ''Execution attributs')}
Invoke-Scenario -Label 'Execute no longer treated as a mutation by the context gate' -ExpectedFailure @('Automation policy off aborts before any directory read','A workstation outside the domain cannot execute') -Mutation {param($t,$s);Mutate-Runtime $t @('-ReadOnly:($Action -eq ''AttributeObserve'' -or -not $Execute)','-ReadOnly:($Action -eq ''AttributeObserve'' -or $Execute)')}
Invoke-Scenario -Label 'Preview no longer opened as a read-only context' -ExpectedFailure @('A read-only session prepares a diff but cannot execute') -Mutation {param($t,$s);Mutate-Runtime $t @('-ReadOnly:($Action -eq ''AttributeObserve'' -or -not $Execute)','-ReadOnly:($Action -eq ''AttributeObserve'')')}
Invoke-Scenario -Label 'Observation accepts execution' -ExpectedFailure @('AttributeObserve refuses -Execute and never writes AD') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Action -eq ''AttributeObserve''){if($Execute){throw ''Observation sans execution.''','if($Action -eq ''AttributeObserve''){if($false){throw ''Observation sans execution.''')}
Invoke-Scenario -Label 'Attribute execution bypasses the idempotency ledger' -ExpectedFailure @('Replaying the same idempotency key never writes AD twice','The idempotency key is durably recorded before the AD write') -Mutation {param($t,$s);Mutate-Runtime $t @('''Attributes''{return Invoke-PestoIdempotentExecution -Key $IdempotencyKey -Payload ([pscustomobject]@{Action=''Attributes'';Plan=$plan;Approval=$Approval}) -Handler {Invoke-PestoAttributeMutation $plan $Approval}}','''Attributes''{return Invoke-PestoAttributeMutation $plan $Approval}')}
Invoke-Scenario -Label 'Observation no longer routed through the attribute branch' -ExpectedFailure @('AttributeObserve refuses -Execute and never writes AD') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Action -eq ''Attributes'' -or $Action -eq ''AttributeObserve''){','if($Action -eq ''Attributes''){')}
Invoke-Scenario -Label 'Idempotency key grammar unchecked' -ExpectedFailure @('A key outside the ASCII grammar is refused before any write') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Key -cnotmatch ''^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$''){','if($false){')}
Invoke-Scenario -Label 'Recorded request fingerprint ignored' -ExpectedFailure @('The same key with another plan is refused and never replayed') -Mutation {param($t,$s);Mutate-Runtime $t @('$saved.PayloadHash -cne $payloadHash','$false')}
Invoke-Scenario -Label 'Recorded operator machine ignored' -ExpectedFailure @('A record taken over by another operator machine is not replayed') -Mutation {param($t,$s);Mutate-Runtime $t @('$saved.MachineId -ine $machine','$false')}
Invoke-Scenario -Label 'Completed record no longer replayed' -ExpectedFailure @('Replaying the same idempotency key never writes AD twice','A refused execution stays recorded under its key') -Mutation {param($t,$s);Mutate-Runtime $t @('if($saved.Status -ceq ''Completed'' -and $saved.Result','if($false -and $saved.Result')}
Invoke-Scenario -Label 'Replay no longer marked as replayed' -ExpectedFailure @('Replaying the same idempotency key never writes AD twice') -Mutation {param($t,$s);Mutate-Runtime $t @('$saved.Result|Add-Member -NotePropertyName Replayed -NotePropertyValue $true -Force','$saved.Result|Out-Null')}
Invoke-Scenario -Label 'Idempotency record written after the handler instead of before' -ExpectedFailure @('The idempotency key is durably recorded before the AD write') -Mutation {param($t,$s);Mutate-Runtime $t @('Write-PestoJoinReceipt -Path $path -Receipt $record{NL}        $started=$true{NL}        $returned=@(& $Handler)','$started=$true{NL}        $returned=@(& $Handler){NL}        Write-PestoJoinReceipt -Path $path -Receipt $record')}
Invoke-Scenario -Label 'Simulation flags no longer refused' -ExpectedFailure @('A simulation flag in the configuration aborts the entry') -Mutation {param($t,$s);Mutate-Runtime $t @('foreach($flag in @(''Simulation'',''GUI'',''HorsDomaine'',''MauvaiseOU'',''ForceADM'',''BPVerifNomAD'')){{NL}        if($script:CFG.DEBUG','foreach($flag in @()){{NL}        if($script:CFG.DEBUG')}
Invoke-Scenario -Label 'Automation policy gate removed' -ExpectedFailure @('Automation policy off aborts before any directory read','A read-only session prepares a diff but cannot execute') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and (-not $script:PestoPolicy.UnattendedOperationsEnabled -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq ''1'')){','if($false){')}
Invoke-Scenario -Label 'Domain member gate removed' -ExpectedFailure @('A workstation outside the domain cannot execute') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and -not $script:INDOMAIN){','if($false){')}
Invoke-Scenario -Label 'Credential type gate removed' -ExpectedFailure @('A credential handed over as text is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($null -ne $Credential -and ($Credential -isnot [Management.Automation.PSCredential]','if($false -and ($Credential -isnot [Management.Automation.PSCredential]')}
Invoke-Scenario -Label 'Discovered controller no longer checked against the domain' -ExpectedFailure @('A domain controller of another domain aborts before any directory read') -Mutation {param($t,$s);Mutate-Runtime $t @('if($domain.DNSRoot -ine $script:DOMAINE){','if($false){')}
Invoke-Scenario -Label 'Relative export path accepted' -ExpectedFailure @('Relative plan paths are refused before any read') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not[IO.Path]::IsPathRooted($Path)){throw ''Chemin de plan absolu requis.''','if($false){throw ''Chemin de plan absolu requis.''')}
Invoke-Scenario -Label 'Relative document path accepted' -ExpectedFailure @('Relative plan paths are refused before any read') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not[IO.Path]::IsPathRooted($Path)){throw ''Un chemin absolu est requis.''','if($false){throw ''Un chemin absolu est requis.''')}
Invoke-Scenario -Label 'Oversized document accepted' -ExpectedFailure @('A plan file beyond the read limit is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($f.PSIsContainer -or $f.Length -gt $MaximumBytes){','if($false){')}
Invoke-Scenario -Label 'Plan export silently overwrites a handed-over plan' -ExpectedFailure @('The same export path is never silently overwritten') -Mutation {param($t,$s);Mutate-Runtime $t @('$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None){NL}    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)','$stream=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None){NL}    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)')}
Invoke-Scenario -Label 'Plan dates left as converted objects' -ExpectedFailure @('A plan file rewritten by an orchestrator still executes') -Mutation {param($t,$s);Mutate-Runtime $t @('foreach($date in @(''CreatedUtc'',''ExpiresUtc'')){if($Plan.$date -is [DateTime]){$Plan.$date=$Plan.$date.ToUniversalTime().ToString(''o'')}}','foreach($date in @(''CreatedUtc'',''ExpiresUtc'')){}')}
Invoke-Scenario -Label 'Read-only session gate removed on both legs' -ExpectedFailure @('A read-only session prepares a diff but cannot execute') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and (-not $script:PestoPolicy.UnattendedOperationsEnabled -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq ''1'')){','if(-not $ReadOnly -and (-not $script:PestoPolicy.UnattendedOperationsEnabled -or $script:PestoPolicy.IncidentMode)){','if($env:PESTO_READONLY_SESSION -eq ''1''){throw ''Session','if($false){throw ''Session')}
Invoke-Scenario -Label 'Requested attribute whitelist widened at the entry' -ExpectedFailure @('An attribute outside the three allowed is refused through the entry') -Mutation {param($t,$s);Mutate-Runtime $t @('Assert-PestoClosedObject $Requested @(''description'',''location'',''managedBy'') @()','Assert-PestoClosedObject $Requested @(''description'',''location'',''managedBy'',''userAccountControl'',''distinguishedName'',''userPassword'') @()')}

Write-Output "AttributeEntry114Mutations : $n/$n PASS"

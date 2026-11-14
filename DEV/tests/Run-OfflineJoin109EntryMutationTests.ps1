#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109EntryTests.ps1 (point d'entree public de la jonction hors
# connexion, point 109) : chaque mutation d'une copie hors sac du moteur doit faire echouer exactement le
# controle de la garde visee (exit 1) et la copie temoin doit passer. Sont frappees ici les gardes propres a
# l'evaluation « blob secret » : contexte hors connexion (drapeaux DEBUG, AllowOfflineJoin, mode incident,
# session en consultation, incompatibilite de coordination et d'exclusion de groupes), exigence -Execute de
# l'import et de l'application, refus d'observer en execution, aiguillage du switch, grammaire de l'identifiant
# de blob, etat local du poste, GUID et OU provisionnes, taille du blob, import unique, garde du recu ODJ et
# empreinte du plan, contexte d'application et echeance, court-circuit d'une demande deja enregistree, taille du
# secret, controle du blob dechiffre, creation exclusive du fichier transitoire, intention durable avant l'appel
# natif, nettoyage du clair et du secret, et les gardes de l'observation (blob non applique, canal securise,
# identite dans l'annuaire, coherence du recu d'intervention). La session en consultation est frappee en paire :
# seule, l'autre jambe masquerait la mutation. L'AD, la plateforme, DPAPI, djoin, les ACL et les magasins restent
# des doubles locaux : aucun appel reseau, aucune VM, aucun cfg.json operationnel lu. La copie se limite au
# moteur requis par la suite, au modele neutre de configuration et a la suite elle-meme.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109EntryTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109EntryTests.ps1'
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutOffline109-'+[Guid]::NewGuid().ToString('N'))
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
        # L'enfant s'etablit dans la copie : un mutant qui accepterait un chemin de blob relatif ecrirait son
        # fichier dans le repertoire courant, donc cette fuite doit rester dans le sac detruit, jamais dans le depot.
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
            Check ($flat -match 'OfflineJoin109Entry: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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

Invoke-Scenario -Label 'DEBUG flags no longer refused for offline join' -ExpectedFailure @('A debug flag in the configuration aborts the import') -Mutation {param($t,$s);Mutate-Runtime $t @('foreach($flag in @(''Simulation'',''GUI'',''HorsDomaine'',''MauvaiseOU'',''ForceADM'',''BPVerifNomAD'')){if($script:CFG.DEBUG','foreach($flag in @()){if($script:CFG.DEBUG')}
Invoke-Scenario -Label 'Offline join policy gate removed' -ExpectedFailure @('Import refuses while the offline join policy is off', 'Incident mode suspends the offline import') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and (-not $script:PestoPolicy.AllowOfflineJoin -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq ''1'')){throw ''Jonction hors connexion desactivee par la politique.''}','if($false){throw ''Jonction hors connexion desactivee par la politique.''}')}
Invoke-Scenario -Label 'Coordination and group exclusion incompatibility removed' -ExpectedFailure @('A coordination registry is refused for offline join', 'Excluded group identities are refused for offline join') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and ($script:PestoPolicy.CoordinationRoot -or $script:PestoPolicy.ExcludedGroupGuids.Count)){','if($false){')}
Invoke-Scenario -Label 'Import and apply opened as a read-only context' -ExpectedFailure @('Import refuses while the offline join policy is off') -Mutation {param($t,$s);Mutate-Runtime $t @('Initialize-PestoOfflineContext $RuntimeRoot $ConfigPath -ReadOnly:($Action -eq ''OfflineObserve'')','Initialize-PestoOfflineContext $RuntimeRoot $ConfigPath -ReadOnly:$true')}
Invoke-Scenario -Label 'Observation no longer opened as a read-only context' -ExpectedFailure @('A read-only observation never confirms the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('Initialize-PestoOfflineContext $RuntimeRoot $ConfigPath -ReadOnly:($Action -eq ''OfflineObserve'')','Initialize-PestoOfflineContext $RuntimeRoot $ConfigPath -ReadOnly:$false')}
Invoke-Scenario -Label 'Observation accepts execution' -ExpectedFailure @('Observe refuses -Execute and never calls djoin') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Action -eq ''OfflineObserve''){if($Execute){throw ''Observation sans execution.''}','if($Action -eq ''OfflineObserve''){if($false){throw ''Observation sans execution.''}')}
Invoke-Scenario -Label 'Import and apply no longer require an explicit -Execute' -ExpectedFailure @('Import requires an explicit -Execute', 'Apply requires an explicit -Execute') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $Execute){throw ''Import ou application ODJ exige -Execute explicite.''}','if($false){throw ''Import ou application ODJ exige -Execute explicite.''}')}
Invoke-Scenario -Label 'Import no longer routed to the offline import' -ExpectedFailure @('Import protects the blob and publishes only its hash') -Mutation {param($t,$s);Mutate-Runtime $t @('''OfflineImport''{return Import-PestoOfflineBlob $BlobPath $ObjectGuid $TargetOU $Metadata}','''OfflineImport''{return $null}')}
Invoke-Scenario -Label 'Apply no longer routed to the offline application' -ExpectedFailure @('Apply writes the durable intention before djoin and calls it once') -Mutation {param($t,$s);Mutate-Runtime $t @('''OfflineApply''{return Invoke-PestoOfflineApply $BlobId $Approval}','''OfflineApply''{return $null}')}
Invoke-Scenario -Label 'Blob identifier grammar unchecked' -ExpectedFailure @('A blob identifier outside the hexadecimal form is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Id -cnotmatch ''^[a-f0-9]{64}$''){throw ''Identifiant ODJ invalide.''}','if($false){throw ''Identifiant ODJ invalide.''}')}
Invoke-Scenario -Label 'Local workstation gate removed at import' -ExpectedFailure @('A machine already joined to the domain cannot import', 'A pending rename refuses the import', 'A non elevated operator refuses the import', 'A domain controller role refuses the import') -Mutation {param($t,$s);Mutate-Runtime $t @('if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){throw ''ODJ exige un poste local hors domaine, sans renommage en attente.''}','if($false){throw ''ODJ exige un poste local hors domaine, sans renommage en attente.''}')}
Invoke-Scenario -Label 'Provisioning GUID and target OU gate removed' -ExpectedFailure @('The provisioning account GUID is required', 'A target OU outside the configured scope is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($ObjectGuid -eq [Guid]::Empty -or -not(Test-PestoOUInConfiguredScope $TargetOU) -or (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){','if($false){')}
Invoke-Scenario -Label 'Blob size gate removed' -ExpectedFailure @('An empty blob is refused', 'An oversized blob is refused', 'A directory handed over as the blob is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt 1MB){','if($false){')}
Invoke-Scenario -Label 'Already imported blob accepted again' -ExpectedFailure @('The same blob cannot be imported twice') -Mutation {param($t,$s);Mutate-Runtime $t @('if([IO.File]::Exists($paths.State) -or [IO.File]::Exists($paths.Secret)){','if($false){')}
Invoke-Scenario -Label 'Offline receipt guard removed' -ExpectedFailure @('A record whose plan points at another blob is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($r.Schema -ne 1 -or $r.Mode -cne ''OfflineJoin'' -or $r.Id -cne $Id -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $r.Plan.BlobSHA256 -cne $Id){','if($false){')}
Invoke-Scenario -Label 'Plan integrity no longer recomputed from the record' -ExpectedFailure @('A tampered state record is refused before any native call') -Mutation {param($t,$s);Mutate-Runtime $t @('$p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy))','$false')}
Invoke-Scenario -Label 'Application context gate removed' -ExpectedFailure @('A machine renamed after the import cannot apply', 'Another operator machine identity refuses the application', 'An expired application window refuses djoin', 'A configuration change after the import refuses the application') -Mutation {param($t,$s);Mutate-Runtime $t @('if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow){','if($false){')}
Invoke-Scenario -Label 'Expiry no longer checked before the native call' -ExpectedFailure @('An expired application window refuses djoin') -Mutation {param($t,$s);Mutate-Runtime $t @('-or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow){','-or $false){')}
Invoke-Scenario -Label 'Already recorded application no longer short-circuited' -ExpectedFailure @('A second application never calls djoin again', 'An interrupted application stays uncertain and is never replayed', 'A nonzero native code is reported uncertain without replay') -Mutation {param($t,$s);Mutate-Runtime $t @('if($r.State -ne ''Imported''){return','if($false){return')}
Invoke-Scenario -Label 'Protected secret size unchecked' -ExpectedFailure @('An oversized protected file is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($f.Length -gt 2MB){throw ''Secret protege invalide.''}','if($false){throw ''Secret protege invalide.''}')}
Invoke-Scenario -Label 'Decrypted blob no longer compared to the plan' -ExpectedFailure @('A protected file that no longer decrypts to the planned blob is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if((Get-PestoBytesHash $bytes) -cne $Id){throw ''Blob decrypte different du plan.''}','if($false){throw ''Blob decrypte different du plan.''}')}
Invoke-Scenario -Label 'Leftover plaintext file silently overwritten' -ExpectedFailure @('A leftover plaintext file is never silently reused') -Mutation {param($t,$s);Mutate-Runtime $t @('$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)','$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)')}
Invoke-Scenario -Label 'Durable intention no longer persisted before the native call' -ExpectedFailure @('Apply writes the durable intention before djoin and calls it once') -Mutation {param($t,$s);Mutate-Runtime $t @('$script:ActiveIntervention|Add-Member OfflineJoin ''Requested'';Write-PestoIntervention $script:ActiveIntervention','$script:ActiveIntervention|Add-Member OfflineJoin ''Requested''')}
Invoke-Scenario -Label 'Plain and secret files left behind after the native call' -ExpectedFailure @('Apply writes the durable intention before djoin and calls it once') -Mutation {param($t,$s);Mutate-Runtime $t @('if($started){foreach($path in @($paths.Plain,$paths.Secret)){Assert-PestoPlainPath $path;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}}','if($false){foreach($path in @($paths.Plain,$paths.Secret)){Assert-PestoPlainPath $path;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}}')}
Invoke-Scenario -Label 'Observation of an unapplied blob no longer refused' -ExpectedFailure @('Observe refuses a blob that was never applied') -Mutation {param($t,$s);Mutate-Runtime $t @('if($r.State -eq ''Imported''){throw ''Blob non applique.''}','if($false){throw ''Blob non applique.''}')}
Invoke-Scenario -Label 'Secure channel no longer required to verify' -ExpectedFailure @('Observe without a verified secure channel stays uncertain') -Mutation {param($t,$s);Mutate-Runtime $t @('$state=if($localMatches -and $identity -and $secure){''Verified''}else{''Uncertain''}','$state=if($localMatches -and $identity){''Verified''}else{''Uncertain''}')}
Invoke-Scenario -Label 'Directory identity reduced to the computer name' -ExpectedFailure @('Observe refuses a directory object that moved') -Mutation {param($t,$s);Mutate-Runtime $t @('$identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU','$identity=$pc.Name -ieq $p.NewName')}
Invoke-Scenario -Label 'Ledger coherence guard removed' -ExpectedFailure @('Observe refuses a receipt without an offline join intention') -Mutation {param($t,$s);Mutate-Runtime $t @('if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){','if($false){')}
Invoke-Scenario -Label 'Engine policy guard no longer consulted before djoin' -ExpectedFailure @('The engine policy guard suspends the application for an excluded computer', 'The engine policy guard suspends the application for an excluded OU') -Mutation {param($t,$s);Mutate-Runtime $t @('{NL}    Assert-PestoOperationPolicy $effect $script:PestoPolicy{NL}','{NL}    $null = $effect{NL}')}
Invoke-Scenario -Label 'Campaign approval no longer required' -ExpectedFailure @('A campaign tagged offline plan requires an approval') -Mutation {param($t,$s);Mutate-Runtime $t @('Assert-PestoCampaignApproval $p $Approval','$null = $Approval')}
Invoke-Scenario -Label 'Blob hash and plan seal no longer written at import' -ExpectedFailure @('Import protects the blob and publishes only its hash') -Mutation {param($t,$s);Mutate-Runtime $t @('$p|Add-Member BlobSHA256 $sha;$p|Add-Member Integrity (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $p))','$p|Add-Member BlobSHA256 (''0''*64);$p|Add-Member Integrity ''''')}
Invoke-Scenario -Label 'Read-only session ignored on both legs' -ExpectedFailure @('A read-only session refuses the import but a writable one proceeds', 'A read-only observation never confirms the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('if(-not $ReadOnly -and (-not $script:PestoPolicy.AllowOfflineJoin -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq ''1'')){throw ''Jonction hors connexion desactivee par la politique.''}','if(-not $ReadOnly -and (-not $script:PestoPolicy.AllowOfflineJoin -or $script:PestoPolicy.IncidentMode)){throw ''Jonction hors connexion desactivee par la politique.''}','if($state -eq ''Verified'' -and $env:PESTO_READONLY_SESSION -ne ''1''){','if($state -eq ''Verified''){')}

Write-Output "OfflineJoin109EntryMutations : $n/$n PASS"

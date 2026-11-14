#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109ApplyTests.ps1 (application unique du blob secret de la jonction
# hors connexion, point 109). Chaque mutation d'une copie hors sac du moteur doit faire echouer exactement le
# controle de la garde visee (exit non nul) et la copie temoin doit passer. Sont frappees ici les gardes qui
# decident de ce que le blob secret devient quand il quitte le magasin : le garde d'etat qui interdit le rejeu et
# son drapeau de rejeu, les huit conditions du contexte du poste revifiees a l'application (poste joint, renommage
# en attente, administration, role de domaine, nom de poste, identite de machine, marqueur de configuration,
# fenetre de validite du plan), les trois portes (politique, registre local, approbation de campagne), les quatre
# controles du secret (chemin clair, plafond de deux megaoctets, deprotection, empreinte contre le plan scelle),
# l'ordre de l'intention durable avant l'appel natif (recu durable et registre d'intervention), l'ouverture du
# fichier transitoire en CreateNew et son contenu, la destruction des deux fichiers et l'effacement des tampons,
# et la decision rendue par le code de sortie natif (etat, code rendu, redemarrage exige). Les suites existantes
# du point ne frappaient aucune de ces gardes : le sondage consigne dans
# DEV/docs/implementation/proofs/OFFLINE_JOIN_109_APPLY_20261025.json le mesure. L'AD, la plateforme, DPAPI, djoin,
# les ACL, le registre et les magasins restent des doubles locaux : aucun appel reseau, aucune VM, aucun cfg.json
# operationnel lu. La copie se limite au moteur requis par la suite, au modele neutre de configuration et a la
# suite elle-meme.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109ApplyTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109ApplyTests.ps1'
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
function New-Sac{
    # Le sac est pose a cote du depot et non dans le repertoire temporaire systeme : Write-PestoAtomicText
    # flush chaque recu sur le disque, et ce repertoire temporaire est mesure quatorze fois plus lent sur
    # cette machine (dix mille dossiers herites des campagnes precedentes), ce qui ferait depasser au harnais
    # le delai de 900 s de la campagne portable. A defaut d'ecriture a cet endroit, on retombe sur le
    # repertoire temporaire systeme, comme les autres harnais du point.
    $outside=Join-Path (Split-Path (Split-Path $root -Parent) -Parent) ('pesto-mut109apply-'+[Guid]::NewGuid().ToString('N'))
    foreach($candidate in @($outside,(Join-Path ([IO.Path]::GetTempPath()) ('PestoMutApply109-'+[Guid]::NewGuid().ToString('N'))))){
        try{[void][IO.Directory]::CreateDirectory($candidate);return $candidate}catch{}
    }
    throw 'Aucun emplacement de sac disponible pour le harnais.'
}
function Invoke-Scenario{
    param([string]$Label,[scriptblock]$Mutation,[string[]]$ExpectedFailure)
    $temp=New-Sac
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
        # L'enfant s'etablit dans la copie : un mutant qui accepterait un chemin relatif ecrirait ses fichiers dans
        # le repertoire courant, donc cette fuite doit rester dans le sac detruit, jamais dans le depot.
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
            Check ($flat -match 'OfflineJoin109Apply: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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
$etat="if(`$r.State -ne 'Imported'){return [pscustomobject]@{ExitCode=97;"
$rejeu="BlobId=`$Id;ReplayAllowed=`$false;Message='Demande deja enregistree"
$contexte="`$local.PartOfDomain -or `$local.PendingRename -or -not `$local.Admin -or `$local.DomainRole -notin @(0,2) -or `$local.Computer -ine `$p.Computer -or `$local.MachineId -ine `$p.MachineId -or `$p.ConfigStamp -cne (Get-PestoConfigurationSignature `$script:CFG) -or [DateTimeOffset]::Parse(`$p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow"
$plafond="if(`$f.Length -gt 2MB){throw 'Secret protege invalide.'}"
$cheminSecret="Assert-PestoPlainPath `$paths.Secret;`$f=Get-Item"
$empreinte="if((Get-PestoBytesHash `$bytes) -cne `$Id){throw 'Blob decrypte different du plan.'}"
$cheminPlain="Assert-PestoPlainPath `$paths.Plain;`$stream=[IO.File]::Open(`$paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)"
$ecriture="`$stream=[IO.File]::Open(`$paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None){NL}        try{`$stream.Write(`$bytes,0,`$bytes.Length);"
$avantNative="        Write-PestoJoinReceipt `$paths.State `$r{NL}        `$started=`$true"
$lancement="`$r.NativeCode=Invoke-PestoOfflineNative `$paths.Plain"
$intentionRegistre="`$script:ActiveIntervention|Add-Member OfflineJoin 'Requested';Write-PestoIntervention `$script:ActiveIntervention"
$nettoyage="foreach(`$path in @(`$paths.Plain,`$paths.Secret))"
$tampons="foreach(`$buffer in @(`$secret,`$bytes)){if(`$buffer){[Array]::Clear(`$buffer,0,`$buffer.Length)}}"
$etatNatif="`$r.State=if(`$r.NativeCode -eq 0){'PendingRestart'}else{'Uncertain'}"
$codeRendu="ExitCode=`$(if(`$r.NativeCode -eq 0){3010}else{97})"
$redemarrage="RestartRequired=(`$r.NativeCode -eq 0)"
$cheminEchec="if(`$started){`$r.State='Uncertain';try{Write-PestoJoinReceipt `$paths.State `$r}catch{}"
$effet="Action='OfflineJoin';Nom_du_PC=`$p.Computer"
$empreinteEffet="Metadata=`$p.Metadata;BlobSHA256=`$Id}"
$portes="    Assert-PestoOperationPolicy `$effect `$script:PestoPolicy{NL}    Assert-PestoStoredMutationReady -Plan `$effect{NL}    Assert-PestoCampaignApproval `$p `$Approval"

Invoke-Scenario -Label 'Witness' -Mutation $null

Invoke-Scenario -Label 'An already recorded request is applied again' -ExpectedFailure @('A blob already pending restart is never handed to djoin again') -Mutation {param($t,$s);Mutate-Runtime $t @($etat,'if($false){return [pscustomobject]@{ExitCode=97;')}
Invoke-Scenario -Label 'The refusal of a replay announces it as replayable' -ExpectedFailure @('A blob left at Requested by an interrupted run is never handed to djoin again') -Mutation {param($t,$s);Mutate-Runtime $t @($rejeu,"BlobId=`$Id;ReplayAllowed=`$true;Message='Demande deja enregistree")}
Invoke-Scenario -Label 'A machine joined since the import consumes the secret' -ExpectedFailure @('A machine joined between the import and the application cannot consume the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$false -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'A pending rename no longer stops the application' -ExpectedFailure @('A pending rename appearing between the import and the application stops the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $false -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'An operator without administration consumes the secret' -ExpectedFailure @('An operator who lost local administration cannot consume the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $true -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'Any domain role is accepted at application time' -ExpectedFailure @('A machine promoted to domain controller between import and application is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,1,2,3,4,5) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'The renamed machine still consumes the secret' -ExpectedFailure @('The machine that was renamed since the import does not consume the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $false -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'A changed machine identity still consumes the secret' -ExpectedFailure @('A machine whose hardware identity changed since the import does not consume the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $false -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'A configuration edited since the import no longer invalidates the secret' -ExpectedFailure @('A configuration edited between the import and the application invalidates the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $false -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow')}
Invoke-Scenario -Label 'An expired plan still consumes the secret' -ExpectedFailure @('A plan whose validity window elapsed cannot consume the secret') -Mutation {param($t,$s);Mutate-Runtime $t @($contexte,'$local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -lt [DateTimeOffset]::MinValue')}
Invoke-Scenario -Label 'The policy gate is skipped' -ExpectedFailure @('A computer name excluded by policy never reaches djoin') -Mutation {param($t,$s);Mutate-Runtime $t @($portes,"    `$null = `$effect{NL}    Assert-PestoStoredMutationReady -Plan `$effect{NL}    Assert-PestoCampaignApproval `$p `$Approval")}
Invoke-Scenario -Label 'The local register gate is skipped' -ExpectedFailure @('The unresolved-operation gate of the local register stops the secret before djoin') -Mutation {param($t,$s);Mutate-Runtime $t @($portes,"    Assert-PestoOperationPolicy `$effect `$script:PestoPolicy{NL}    `$null = `$effect{NL}    Assert-PestoCampaignApproval `$p `$Approval")}
Invoke-Scenario -Label 'The campaign approval gate is skipped' -ExpectedFailure @('A campaign-gated policy refuses a blob imported without any campaign') -Mutation {param($t,$s);Mutate-Runtime $t @($portes,"    Assert-PestoOperationPolicy `$effect `$script:PestoPolicy{NL}    Assert-PestoStoredMutationReady -Plan `$effect{NL}    `$null = `$Approval")}
Invoke-Scenario -Label 'The protected secret is read through a link without being checked' -ExpectedFailure @('A secret replaced by a symbolic link is refused before being read') -Mutation {param($t,$s);Mutate-Runtime $t @($cheminSecret,'$null = $paths.Secret;$f=Get-Item')}
Invoke-Scenario -Label 'Any size of protected secret is accepted' -ExpectedFailure @('A secret one byte over the two megabyte ceiling is refused before being unprotected') -Mutation {param($t,$s);Mutate-Runtime $t @($plafond,'if($false){throw ''Secret protege invalide.''}')}
Invoke-Scenario -Label 'The unprotected material is no longer compared to the sealed plan' -ExpectedFailure @('A secret that decrypts to something else than the sealed plan is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($empreinte,'if($false){throw ''Blob decrypte different du plan.''}')}
# La reecriture "Assert-PestoPlainPath $paths.Plain" -> "$null = $paths.Plain" n'est pas comptee comme mutant :
# mesuree, elle laisse la suite a 51/51 parce que [IO.FileMode]::CreateNew refuse deja l'ouverture d'un lien, quel
# que soit le sort de sa cible. La garde reste une defense en profondeur (cas comportemental "A plain path replaced
# by a link never lets the blob material leave the store") et les deux mutants ci-dessous frappent la meme ligne.
Invoke-Scenario -Label 'The plain file handed to djoin is left empty' -ExpectedFailure @('The file handed to djoin carries exactly the blob material') -Mutation {param($t,$s);Mutate-Runtime $t @($ecriture,'$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None){NL}        try{$stream.Write($bytes,0,0);')}
Invoke-Scenario -Label 'A leftover plain file is silently overwritten' -ExpectedFailure @('A plain file left on disk by a crash refuses the application and never reaches djoin') -Mutation {param($t,$s);Mutate-Runtime $t @($cheminPlain,'Assert-PestoPlainPath $paths.Plain;$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)')}
Invoke-Scenario -Label 'The plain file is written from the protected bytes instead of the blob' -ExpectedFailure @('The file handed to djoin carries exactly the blob material') -Mutation {param($t,$s);Mutate-Runtime $t @($ecriture,'$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None){NL}        try{$stream.Write($secret,0,$secret.Length);')}
Invoke-Scenario -Label 'The durable intention is written only after djoin answered' -ExpectedFailure @('The durable receipt already reads Requested at the instant djoin is called') -Mutation {param($t,$s);Mutate-Runtime $t @($avantNative,'        $started=$true',$lancement,'$r.NativeCode=Invoke-PestoOfflineNative $paths.Plain{NL}        Write-PestoJoinReceipt $paths.State $r')}
Invoke-Scenario -Label 'The intervention ledger is not persisted before djoin' -ExpectedFailure @('The intervention ledger already carries the offline intention at the instant djoin is called') -Mutation {param($t,$s);Mutate-Runtime $t @($intentionRegistre,"`$script:ActiveIntervention|Add-Member OfflineJoin 'Requested'")}
Invoke-Scenario -Label 'The protected secret survives its single use' -ExpectedFailure @('Both the plain file and the protected secret are destroyed once djoin answered') -Mutation {param($t,$s);Mutate-Runtime $t @($nettoyage,'foreach($path in @($paths.Plain))')}
Invoke-Scenario -Label 'The plain file survives the application' -ExpectedFailure @('Both the plain file and the protected secret are destroyed once djoin answered') -Mutation {param($t,$s);Mutate-Runtime $t @($nettoyage,'foreach($path in @($paths.Secret))')}
Invoke-Scenario -Label 'The clear material is left in memory when the application ends' -ExpectedFailure @('The clear material is wiped from memory when the application ends') -Mutation {param($t,$s);Mutate-Runtime $t @($tampons,'$null = @($secret,$bytes)')}
Invoke-Scenario -Label 'Any native code is treated as a recorded request' -ExpectedFailure @('A nonzero native code leaves the blob Uncertain and asks for no restart') -Mutation {param($t,$s);Mutate-Runtime $t @($etatNatif,"`$r.State=if(`$true){'PendingRestart'}else{'Uncertain'}")}
Invoke-Scenario -Label 'The application always announces a restart' -ExpectedFailure @('A restart code from djoin itself is not mistaken for success') -Mutation {param($t,$s);Mutate-Runtime $t @($codeRendu,'ExitCode=$(if($true){3010}else{97})')}
Invoke-Scenario -Label 'The result always asks for a restart' -ExpectedFailure @('A nonzero native code leaves the blob Uncertain and asks for no restart') -Mutation {param($t,$s);Mutate-Runtime $t @($redemarrage,'RestartRequired=$true')}
Invoke-Scenario -Label 'An interrupted application leaves a replayable state' -ExpectedFailure @('A native timeout is reported as uncertain and never replayed') -Mutation {param($t,$s);Mutate-Runtime $t @($cheminEchec,"if(`$started){`$r.State='Imported';try{Write-PestoJoinReceipt `$paths.State `$r}catch{}")}
Invoke-Scenario -Label 'An interrupted application never persists its uncertainty' -ExpectedFailure @('A native timeout is reported as uncertain and never replayed') -Mutation {param($t,$s);Mutate-Runtime $t @($cheminEchec,"if(`$started){`$r.State='Uncertain';try{`$null = `$paths.State}catch{}")}
Invoke-Scenario -Label 'The effect handed to the gates is a plain online join' -ExpectedFailure @('The effect handed to the gates is an offline join effect for the planned blob') -Mutation {param($t,$s);Mutate-Runtime $t @($effet,"Action='Join';Nom_du_PC=`$p.Computer")}
Invoke-Scenario -Label 'The effect no longer names the blob it consumes' -ExpectedFailure @('The effect handed to the gates is an offline join effect for the planned blob') -Mutation {param($t,$s);Mutate-Runtime $t @($empreinteEffet,'Metadata=$p.Metadata}')}
Invoke-Scenario -Label 'The offline effect asks for a reboot it does not perform' -ExpectedFailure @('The effect handed to the gates is an offline join effect for the planned blob') -Mutation {param($t,$s);Mutate-Runtime $t @('Reboot=$false;Metadata=$p.Metadata','Reboot=$true;Metadata=$p.Metadata')}
Invoke-Scenario -Label 'The native code is never recorded in the durable receipt' -ExpectedFailure @('A zero native code asks for a restart and marks the blob pending restart') -Mutation {param($t,$s);Mutate-Runtime $t @($lancement,'(Invoke-PestoOfflineNative $paths.Plain)|Out-Null')}

Write-Output "OfflineJoin109ApplyMutations : $n/$n PASS"

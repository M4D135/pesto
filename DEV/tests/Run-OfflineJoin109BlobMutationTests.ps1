#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109BlobTests.ps1 (import du blob secret de la jonction hors connexion,
# point 109). Chaque mutation d'une copie hors sac du moteur doit faire echouer exactement le controle de la garde
# visee (exit 1) et la copie temoin doit passer. Sont frappees ici les gardes qui decident de ce qu'un blob secret
# devient a l'entree du magasin : les quatre conditions du statut local du poste, les trois clauses de la garde du
# compte provisionne, les trois formes refusables du materiel, les deux moities du garde de rejeu et son integralite,
# la protection DPAPI et sa portee machine, l'ecriture du secret en base64 et non en clair, l'effacement des deux
# tampons a la sortie, l'ordre de la protection avant toute persistance, la relecture du chemin clair du secret,
# la garde d'empreinte sur l'identifiant (casse, longueur, echappee du magasin), les cinq controles du recu ferme,
# les deux controles d'objet ferme et les neuf controles d'identite et de cible du plan scelle. L'AD, la plateforme,
# DPAPI, djoin, les ACL et les magasins restent des doubles locaux : aucun appel reseau, aucune VM, aucun cfg.json
# operationnel lu. La copie se limite au moteur requis par la suite, au modele neutre de configuration et a la suite
# elle-meme.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109BlobTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109BlobTests.ps1'
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutBlob109-'+[Guid]::NewGuid().ToString('N'))
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
            Check ($flat -match 'OfflineJoin109Blob: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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
$eligibilite='if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){throw '
$compte='if($ObjectGuid -eq [Guid]::Empty -or -not(Test-PestoOUInConfiguredScope $TargetOU) -or (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){throw '
$forme='if($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt 1MB){throw '
$rejeu='if([IO.File]::Exists($paths.State) -or [IO.File]::Exists($paths.Secret)){throw '
$recu='if($r.Schema -ne 1 -or $r.Mode -cne ''OfflineJoin'' -or $r.Id -cne $Id -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $r.Plan.BlobSHA256 -cne $Id){throw '
$cible='if($p.Schema -ne 1 -or -not(Test-PestoComputerName $p.Computer) -or $p.NewName -cne $p.Computer -or -not(Test-PestoOUPath $p.TargetOU)){throw '
$identite='if($p.Action -cne ''OfflineJoin'' -or $p.Purpose -cne ''PestoPreparedPlan'' -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $p.Domain -ine $script:DOMAINE -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw '
$record='OperationId='''';NativeCode=$null;Utc=[DateTime]::UtcNow.ToString(''o'')}'
$cheminSecret='Write-PestoJoinReceipt $paths.State $record{NL}        Assert-PestoPlainPath $paths.Secret'
$portee='ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine'

Invoke-Scenario -Label 'Witness' -Mutation $null

Invoke-Scenario -Label 'Domain-joined machines are no longer refused at import' -ExpectedFailure @('A machine already joined to a domain cannot import a secret blob') -Mutation {param($t,$s);Mutate-Runtime $t @($eligibilite,'if($false -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){throw ')}
Invoke-Scenario -Label 'Pending renames are no longer refused at import' -ExpectedFailure @('A machine with a pending rename cannot import a secret blob') -Mutation {param($t,$s);Mutate-Runtime $t @($eligibilite,'if($local.PartOfDomain -or $false -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){throw ')}
Invoke-Scenario -Label 'Non administrators are no longer refused at import' -ExpectedFailure @('An operator without local administration cannot import a secret blob') -Mutation {param($t,$s);Mutate-Runtime $t @($eligibilite,'if($local.PartOfDomain -or $local.PendingRename -or $false -or $local.DomainRole -notin @(0,2)){throw ')}
Invoke-Scenario -Label 'Controller roles are no longer refused at import' -ExpectedFailure @('A domain controller role cannot import a secret blob') -Mutation {param($t,$s);Mutate-Runtime $t @('$local.DomainRole -notin @(0,2)){throw ''ODJ exige',' $local.DomainRole -notin @(0,1,2,3,4,5)){throw ''ODJ exige')}
Invoke-Scenario -Label 'The all-zero provisioning account is no longer refused' -ExpectedFailure @('The all-zero provisioning account GUID is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($compte,'if($false -or -not(Test-PestoOUInConfiguredScope $TargetOU) -or (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){throw ')}
Invoke-Scenario -Label 'Organisational units outside the configured scope are no longer refused' -ExpectedFailure @('An organisational unit outside the configured scope is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($compte,'if($ObjectGuid -eq [Guid]::Empty -or $false -or (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){throw ')}
Invoke-Scenario -Label 'Empty blobs are no longer refused' -ExpectedFailure @('An empty blob is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($forme,'if($file.PSIsContainer -or $false -or $file.Length -gt 1MB){throw ')}
Invoke-Scenario -Label 'Oversized blobs are no longer refused' -ExpectedFailure @('A blob one byte over the megabyte ceiling is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($forme,'if($file.PSIsContainer -or $file.Length -lt 1 -or $false){throw ')}
Invoke-Scenario -Label 'A directory handed over as the blob is no longer refused' -ExpectedFailure @('A directory handed over as the blob is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($forme,'if($false -or $file.Length -lt 1 -or $file.Length -gt 1MB){throw ')}
Invoke-Scenario -Label 'A replay is no longer refused when only the secret is left' -ExpectedFailure @('A replay is still refused when only the protected secret is left on disk') -Mutation {param($t,$s);Mutate-Runtime $t @($rejeu,'if([IO.File]::Exists($paths.State)){throw ')}
Invoke-Scenario -Label 'A replay is no longer refused when only the receipt is left' -ExpectedFailure @('A replay is still refused when only the state receipt is left on disk') -Mutation {param($t,$s);Mutate-Runtime $t @($rejeu,'if([IO.File]::Exists($paths.Secret)){throw ')}
Invoke-Scenario -Label 'A blob can be imported over and over' -ExpectedFailure @('The same blob cannot be imported a second time') -Mutation {param($t,$s);Mutate-Runtime $t @($rejeu,'if($false){throw ')}
Invoke-Scenario -Label 'The clear path of the secret is no longer re-checked before it is written' -ExpectedFailure @('The material is protected before anything is persisted and the secret path is re-checked before it is written') -Mutation {param($t,$s);Mutate-Runtime $t @($cheminSecret,'Write-PestoJoinReceipt $paths.State $record{NL}        $null = $paths.Secret')}
Invoke-Scenario -Label 'The secret file is written from the clear material instead of the protected one' -ExpectedFailure @('The protected file is the base64 of the protected material and decodes back to the blob') -Mutation {param($t,$s);Mutate-Runtime $t @('Write-PestoAtomicText $paths.Secret ([Convert]::ToBase64String($encrypted))','Write-PestoAtomicText $paths.Secret ([Convert]::ToBase64String($bytes))')}
Invoke-Scenario -Label 'The receipt carries the blob material' -ExpectedFailure @('Nothing in the store carries the blob in the clear, nor the secret in the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @($record,'OperationId='''';NativeCode=$null;Utc=[DateTime]::UtcNow.ToString(''o'');Clear=[Convert]::ToBase64String($bytes)}')}
Invoke-Scenario -Label 'The plan keeps the plain join action instead of the offline one' -ExpectedFailure @('The plan is an offline join plan for the configured domain and the planned organisational unit') -Mutation {param($t,$s);Mutate-Runtime $t @('$p.Action=''OfflineJoin'';','$p.Action=''Join'';')}
Invoke-Scenario -Label 'The plan no longer carries the blob fingerprint' -ExpectedFailure @('The plan is an offline join plan for the configured domain and the planned organisational unit') -Mutation {param($t,$s);Mutate-Runtime $t @('$p|Add-Member BlobSHA256 $sha;','')}
Invoke-Scenario -Label 'The plan is no longer sealed on import' -ExpectedFailure @('The sealed plan of the receipt verifies independently of the product') -Mutation {param($t,$s);Mutate-Runtime $t @('$p|Add-Member BlobSHA256 $sha;$p|Add-Member Integrity (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $p))','$p|Add-Member BlobSHA256 $sha;$p|Add-Member Integrity (''0''*64)')}
Invoke-Scenario -Label 'The blob is protected for the importing user instead of the machine' -ExpectedFailure @('The blob is protected for the machine, not for the operator who imports it') -Mutation {param($t,$s);Mutate-Runtime $t @($portee,'ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser')}
Invoke-Scenario -Label 'The clear material is left in memory when the import ends' -ExpectedFailure @('Both the clear material and the protected material are wiped when the import ends') -Mutation {param($t,$s);Mutate-Runtime $t @('}finally{[Array]::Clear($bytes,0,$bytes.Length);if($encrypted){','}finally{if($encrypted){')}
Invoke-Scenario -Label 'The import claims the operator source was consumed' -ExpectedFailure @('The product never deletes the operator source file') -Mutation {param($t,$s);Mutate-Runtime $t @('SourceRetained=$true','SourceRetained=$false')}
Invoke-Scenario -Label 'The receipt is written before the material is protected' -ExpectedFailure @('When the protection fails, neither the receipt nor the secret is persisted') -Mutation {param($t,$s);Mutate-Runtime $t @('$encrypted=(Protect-PestoOfflineBytes $bytes)','$encrypted=$null','Write-PestoJoinReceipt $paths.State $record','Write-PestoJoinReceipt $paths.State $record;$encrypted=(Protect-PestoOfflineBytes $bytes)')}
Invoke-Scenario -Label 'Blob identifiers are matched without case sensitivity' -ExpectedFailure @('A blob identifier written in upper case is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Id -cnotmatch ''^[a-f0-9]{64}$''){throw','if($Id -notmatch ''^[a-f0-9]{64}$''){throw')}
Invoke-Scenario -Label 'Blob identifiers are no longer required to be a fingerprint' -ExpectedFailure @('A blob identifier one character short is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Id -cnotmatch ''^[a-f0-9]{64}$''){throw','if($Id -cnotmatch ''^[a-f0-9]+$''){throw')}
Invoke-Scenario -Label 'Blob identifiers are taken as they come' -ExpectedFailure @('A blob identifier that walks out of the store is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($Id -cnotmatch ''^[a-f0-9]{64}$''){throw ''Identifiant ODJ invalide.''}','if($false){throw ''Identifiant ODJ invalide.''}')}
Invoke-Scenario -Label 'The receipt schema number is no longer checked' -ExpectedFailure @('A receipt declaring another schema is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($recu,'if($false -or $r.Mode -cne ''OfflineJoin'' -or $r.Id -cne $Id -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $r.Plan.BlobSHA256 -cne $Id){throw ')}
Invoke-Scenario -Label 'The receipt mode is no longer checked' -ExpectedFailure @('A receipt declaring another mode than offline join is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($recu,'if($r.Schema -ne 1 -or $false -or $r.Id -cne $Id -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $r.Plan.BlobSHA256 -cne $Id){throw ')}
Invoke-Scenario -Label 'The receipt is no longer required to name the blob asked for' -ExpectedFailure @('A receipt naming another blob than the one asked for is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($recu,'if($r.Schema -ne 1 -or $r.Mode -cne ''OfflineJoin'' -or $false -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $r.Plan.BlobSHA256 -cne $Id){throw ')}
Invoke-Scenario -Label 'The receipt accepts any state' -ExpectedFailure @('A receipt carrying a state outside the closed set is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('-cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'')','-cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'',''Applied'',''Bogus'')')}
Invoke-Scenario -Label 'The receipt is no longer required to match its plan fingerprint' -ExpectedFailure @('A receipt whose plan was sealed for another blob fingerprint is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($recu,'if($r.Schema -ne 1 -or $r.Mode -cne ''OfflineJoin'' -or $r.Id -cne $Id -or $r.State -cnotin @(''Imported'',''Requested'',''PendingRestart'',''Uncertain'',''Verified'') -or $false){throw ')}
Invoke-Scenario -Label 'The receipt is no longer required to be a closed object' -ExpectedFailure @('A receipt carrying an extra field is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('Assert-PestoClosedObject $r @(''Schema'',''Mode'',''Id'',''State'',''Plan'',''BootUtc'',''OperationId'',''NativeCode'',''Utc'') @(''Schema'',''Mode'',''Id'',''State'',''Plan'',''BootUtc'',''OperationId'',''NativeCode'',''Utc'')','$null = $r')}
Invoke-Scenario -Label 'The plan is no longer required to be a closed object' -ExpectedFailure @('A plan carrying an extra field is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('Assert-PestoClosedObject $p @(''Schema'',''Purpose'',''Action'',''CreatedUtc'',''ExpiresUtc'',''MachineId'',''ConfigStamp'',''Domain'',''Computer'',''NewName'',''SourceOU'',''TargetOU'',''ObjectGuid'',''TargetOUGuid'',''Type'',''SiteCode'',''ServiceCode'',''Metadata'',''BlobSHA256'',''Integrity'') @(''Schema'',''Purpose'',''Action'',''CreatedUtc'',''ExpiresUtc'',''MachineId'',''ConfigStamp'',''Domain'',''Computer'',''NewName'',''TargetOU'',''ObjectGuid'',''BlobSHA256'',''Integrity'')','$null = $p')}
Invoke-Scenario -Label 'The plan action is no longer checked on reread' -ExpectedFailure @('A plan sealed for another action than offline join is refused even resealed') -Mutation {param($t,$s);Mutate-Runtime $t @($identite,'if($false -or $p.Purpose -cne ''PestoPreparedPlan'' -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $p.Domain -ine $script:DOMAINE -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw ')}
Invoke-Scenario -Label 'The plan purpose is no longer checked on reread' -ExpectedFailure @('A plan sealed for another purpose than a prepared plan is refused even resealed') -Mutation {param($t,$s);Mutate-Runtime $t @($identite,'if($p.Action -cne ''OfflineJoin'' -or $false -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $p.Domain -ine $script:DOMAINE -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw ')}
Invoke-Scenario -Label 'The plan seal is no longer recomputed on reread' -ExpectedFailure @('A plan whose seal was altered is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($identite,'if($p.Action -cne ''OfflineJoin'' -or $p.Purpose -cne ''PestoPreparedPlan'' -or $false -or $p.Domain -ine $script:DOMAINE -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw ')}
Invoke-Scenario -Label 'The plan domain is no longer checked on reread' -ExpectedFailure @('A plan sealed for another domain is refused even resealed') -Mutation {param($t,$s);Mutate-Runtime $t @($identite,'if($p.Action -cne ''OfflineJoin'' -or $p.Purpose -cne ''PestoPreparedPlan'' -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $false -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw ')}
Invoke-Scenario -Label 'The plan machine identity is no longer checked on reread' -ExpectedFailure @('A plan sealed for another machine is refused even resealed') -Mutation {param($t,$s);Mutate-Runtime $t @($identite,'if($p.Action -cne ''OfflineJoin'' -or $p.Purpose -cne ''PestoPreparedPlan'' -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $p.Domain -ine $script:DOMAINE){throw ')}
Invoke-Scenario -Label 'The plan computer name is no longer validated on reread' -ExpectedFailure @('A plan naming an impossible computer name is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($cible,'if($p.Schema -ne 1 -or $false -or $p.NewName -cne $p.Computer -or -not(Test-PestoOUPath $p.TargetOU)){throw ')}
Invoke-Scenario -Label 'The plan may rename the machine behind the offline join' -ExpectedFailure @('A plan that renames the machine behind the offline join is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($cible,'if($p.Schema -ne 1 -or -not(Test-PestoComputerName $p.Computer) -or $false -or -not(Test-PestoOUPath $p.TargetOU)){throw ')}
Invoke-Scenario -Label 'The plan target organisational unit is no longer validated on reread' -ExpectedFailure @('A plan naming a container instead of an organisational unit is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($cible,'if($p.Schema -ne 1 -or -not(Test-PestoComputerName $p.Computer) -or $p.NewName -cne $p.Computer -or $false){throw ')}
Invoke-Scenario -Label 'The plan schema number is no longer checked on reread' -ExpectedFailure @('A plan declaring another schema is refused') -Mutation {param($t,$s);Mutate-Runtime $t @($cible,'if($false -or -not(Test-PestoComputerName $p.Computer) -or $p.NewName -cne $p.Computer -or -not(Test-PestoOUPath $p.TargetOU)){throw ')}

Write-Output "OfflineJoin109BlobMutations : $n/$n PASS"

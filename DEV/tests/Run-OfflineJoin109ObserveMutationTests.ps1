#requires -Version 5.1
$ErrorActionPreference='Stop'
# Non-tautologie rejouable de Run-OfflineJoin109ObserveTests.ps1 (jambe d'observation de la jonction hors
# connexion, point 109). Chaque mutation d'une copie hors sac du moteur doit faire echouer exactement le controle
# de la garde visee (exit 1) et la copie temoin doit passer. Sont frappees ici les gardes qui decident de l'etat
# final d'un blob secret apres redemarrage : les six conditions de la confrontation locale (poste joint, domaine,
# nom, identite de machine, renommage en attente, redemarrage reellement posterieur a la demande, y compris son
# affaiblissement en -ge), les trois comparaisons de l'objet de l'annuaire (nom, GUID, unite organisationnelle),
# la decision qui exige les trois jambes, la jambe d'annuaire jouee a tort quand la confrontation locale a echoue,
# la decouverte du controleur pour le domaine planifie, l'adressage du canal securise et de la relecture AD,
# l'import du module ActiveDirectory, les trois controles croises du recu d'intervention, la session en
# consultation qui ne doit rien clos, la cloture durable du recu, le code de sortie, la mention en lecture seule
# et le refus d'observer un blob jamais applique. L'AD, la plateforme, DPAPI, djoin, les ACL et les magasins
# restent des doubles locaux : aucun appel reseau, aucune VM, aucun cfg.json operationnel lu. La copie se limite
# au moteur requis par la suite, au modele neutre de configuration et a la suite elle-meme.
$root=Split-Path $PSScriptRoot -Parent
$suiteSource=Join-Path $PSScriptRoot 'Run-OfflineJoin109ObserveTests.ps1'
$suiteRelative='tests/Run-OfflineJoin109ObserveTests.ps1'
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
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoMutObserve109-'+[Guid]::NewGuid().ToString('N'))
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
            Check ($flat -match 'OfflineJoin109Observe: \d+ passed, 0 failed') ($Label+': witness summary line missing')
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

Invoke-Scenario -Label 'Local domain comparison dropped from the observation conjunction' -ExpectedFailure @('A machine joined to another domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $true -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Local computer name dropped from the observation conjunction' -ExpectedFailure @('A machine whose name differs from the plan is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $true -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Local machine identity dropped from the observation conjunction' -ExpectedFailure @('A machine whose machine identity changed is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $true -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Pending rename dropped from the observation conjunction' -ExpectedFailure @('A machine with a pending rename is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and $true -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Reboot comparison dropped from the observation conjunction' -ExpectedFailure @('A boot identical to the recorded boot is not a reboot') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and $true')}
Invoke-Scenario -Label 'Reboot comparison weakened to -ge' -ExpectedFailure @('A boot identical to the recorded boot is not a reboot') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -ge [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Domain-joined flag dropped from the observation conjunction' -ExpectedFailure @('A machine not joined to the domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','$localMatches=$true -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)')}
Invoke-Scenario -Label 'Directory GUID comparison dropped' -ExpectedFailure @('A directory object with another GUID is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU','$identity=$pc.Name -ieq $p.NewName -and $true -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU')}
Invoke-Scenario -Label 'Directory name comparison dropped' -ExpectedFailure @('A directory object renamed in the directory is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU','$identity=$true -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU')}
Invoke-Scenario -Label 'Directory OU comparison dropped' -ExpectedFailure @('A directory object moved out of the planned OU is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU','$identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid')}
Invoke-Scenario -Label 'Directory identity no longer required to verify' -ExpectedFailure @('A directory object with another GUID is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('$state=if($localMatches -and $identity -and $secure){''Verified''}else{''Uncertain''}','$state=if($localMatches -and $secure){''Verified''}else{''Uncertain''}')}
Invoke-Scenario -Label 'Secure channel no longer required to verify' -ExpectedFailure @('An unverified secure channel never closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$state=if($localMatches -and $identity -and $secure){''Verified''}else{''Uncertain''}','$state=if($localMatches -and $identity){''Verified''}else{''Uncertain''}')}
Invoke-Scenario -Label 'Reboot compared to the record write time instead of the recorded boot' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('[DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)','[DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.Utc)')}
Invoke-Scenario -Label 'Directory leg played even when the local confrontation failed' -ExpectedFailure @('A machine not joined to the domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('if($localMatches){','if($true){')}
Invoke-Scenario -Label 'Active Directory module no longer imported' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('Import-PestoADModule (Join-Path $RuntimeRoot ''ActiveDirectory.psd1'')','$null = $RuntimeRoot')}
Invoke-Scenario -Label 'Secure channel asked of another machine than the discovered controller' -ExpectedFailure @('An unverified secure channel never closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$secure=[bool](Test-ComputerSecureChannel -Server $script:DC -ErrorAction Stop)','$secure=[bool](Test-ComputerSecureChannel -Server $p.Domain -ErrorAction Stop)')}
Invoke-Scenario -Label 'Controller discovered for another value than the planned domain' -ExpectedFailure @('The controller is discovered for the planned domain and used for both checks') -Mutation {param($t,$s);Mutate-Runtime $t @('$script:DC=Get-DomainController $p.Domain','$script:DC=Get-DomainController $p.TargetOU')}
Invoke-Scenario -Label 'Directory read addressed by name instead of the planned GUID' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('-Identity ([Guid]$p.ObjectGuid) -Properties DistinguishedName,ObjectGUID','-Identity $p.NewName -Properties DistinguishedName,ObjectGUID')}
Invoke-Scenario -Label 'Ledger computer name no longer cross-checked' -ExpectedFailure @('A ledger naming another computer is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){','if($ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){')}
Invoke-Scenario -Label 'Ledger domain no longer cross-checked' -ExpectedFailure @('A ledger belonging to another domain is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){','if($ledger.Plan.Nom_du_PC -ine $p.Computer -or -not $ledger.OfflineJoin){')}
Invoke-Scenario -Label 'Ledger offline intention no longer cross-checked' -ExpectedFailure @('A ledger without an offline join intention is refused') -Mutation {param($t,$s);Mutate-Runtime $t @('if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){','if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain){')}
Invoke-Scenario -Label 'Read-only session ignored when closing the receipt' -ExpectedFailure @('A read-only observation reports verified without closing anything') -Mutation {param($t,$s);Mutate-Runtime $t @('if($state -eq ''Verified'' -and $env:PESTO_READONLY_SESSION -ne ''1''){','if($state -eq ''Verified''){')}
Invoke-Scenario -Label 'Ledger intention no longer marked verified' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$ledger.OfflineJoin=''Verified'';$ledger.Phase=''Verified''','$ledger.OfflineJoin=''PendingRestart'';$ledger.Phase=''Verified''')}
Invoke-Scenario -Label 'Ledger phase no longer marked verified' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$ledger.OfflineJoin=''Verified'';$ledger.Phase=''Verified''','$ledger.OfflineJoin=''Verified'';$ledger.Phase=''PendingRestart''')}
Invoke-Scenario -Label 'Ledger result code no longer set to verified' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$ledger.ResultCode=30','$ledger.ResultCode=10')}
Invoke-Scenario -Label 'Verifier of the receipt no longer recorded' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$ledger.VerifiedBy=Get-PestoOperatorSid','$ledger.VerifiedBy=''''')}
Invoke-Scenario -Label 'Durable record no longer closed after a verified observation' -ExpectedFailure @('Reconciled observation verifies and closes the receipt') -Mutation {param($t,$s);Mutate-Runtime $t @('$r.State=''Verified'';Write-PestoJoinReceipt (Get-PestoOfflinePaths $Id).State $r','$r.State=''Verified''')}
Invoke-Scenario -Label 'Uncertain observation reported a successful exit code' -ExpectedFailure @('A machine not joined to the domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('ExitCode=$(if($state -eq ''Verified''){0}else{97})','ExitCode=0')}
Invoke-Scenario -Label 'Observation no longer declared read-only' -ExpectedFailure @('A machine not joined to the domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('SecureChannel=$secure;TargetReadOnly=$true;ReplayAllowed=$false}','SecureChannel=$secure;TargetReadOnly=$false;ReplayAllowed=$false}')}
Invoke-Scenario -Label 'Observation declared replayable' -ExpectedFailure @('A machine not joined to the domain is never verified') -Mutation {param($t,$s);Mutate-Runtime $t @('SecureChannel=$secure;TargetReadOnly=$true;ReplayAllowed=$false}','SecureChannel=$secure;TargetReadOnly=$true;ReplayAllowed=$true}')}
Invoke-Scenario -Label 'Unapplied blob no longer refused by the observation' -ExpectedFailure @('Observation of a record still at Imported is refused before any directory read') -Mutation {param($t,$s);Mutate-Runtime $t @('if($r.State -eq ''Imported''){throw ''Blob non applique.''}','if($false){throw ''Blob non applique.''}')}

Write-Output "OfflineJoin109ObserveMutations : $n/$n PASS"

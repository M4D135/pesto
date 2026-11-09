#requires -Version 5.1
# Diagnostics explicites et en lecture seule. Ne changent ni DC, DNS, heure, SPN ni sécurité.
function New-PestoDiagnosticFinding {
    param([string]$Name,[ValidateSet('Observed','Refused','Unknown','Warning')][string]$State,[string]$Detail,$Data=$null)
    # Reuse only an assembly registered by the verified common loader. Importing
    # the engine alone must not load a DLL or change the structured Data object.
    if($Detail.Length -gt 16384){$Detail=$Detail.Substring(0,16372)+' [tronqué]'}
    $commonType='M4D.Admin.Common.Diagnostics.Redaction' -as [type]
    $registry=[AppDomain]::CurrentDomain.GetData('Pesto.Common.VerifiedAssemblies.v1')
    if($commonType -and $registry -is [hashtable]){
        $known=$registry['M4D.Admin.Common.Diagnostics']
        if($known -is [hashtable] -and [object]::ReferenceEquals($known.Assembly,$commonType.Assembly)){$Detail=$commonType::Mask($Detail)}
    }
    [pscustomobject]@{PSTypeName='Pesto.Diagnostic.Finding';Name=$Name;State=$State;Detail=(Protect-PestoLogText $Detail);Data=$Data;ObservedUtc=[DateTime]::UtcNow.ToString('o');ReadOnly=$true}
}
function Get-PestoDiagnosticActions {
    @(
        [pscustomobject]@{Id='Network';Label='DNS et transports';Reads=@('Suffixes DNS','SRV','DC découvert Windows','Ports de l''action');Writes=$false},
        [pscustomobject]@{Id='Clock';Label='Écart d''horloge';Reads=@('Observation w32tm sur le DC sélectionné');Writes=$false},
        [pscustomobject]@{Id='Account';Label='Compte machine et SPN';Reads=@('Objet AD','DNSHostName','SPN');Writes=$false},
        [pscustomobject]@{Id='Restart';Label='Pourquoi redémarrer';Reads=@('Noms actif et configuré','CBS','Windows Update','Renommages de fichiers');Writes=$false},
        [pscustomobject]@{Id='NetSetup';Label='Journal Windows de jonction';Reads=@('Intervalle et noms du reçu');Writes=$false}
    )
}
function Test-PestoDiagnosticEndpoint {
    param([string]$HostName,[ValidateRange(1,65535)][int]$Port,[ValidateRange(100,10000)][int]$TimeoutMilliseconds=1500)
    if(-not(Test-PestoDnsName $HostName)){throw 'Hôte de diagnostic invalide.'}
    $client=[Net.Sockets.TcpClient]::new();$async=$null;$clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $async=$client.BeginConnect($HostName,$Port,$null,$null)
        if(-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)){return [pscustomobject]@{Host=$HostName;Port=$Port;Reachable=$false;State='Timeout';Milliseconds=$clock.ElapsedMilliseconds}}
        $client.EndConnect($async)
        return [pscustomobject]@{Host=$HostName;Port=$Port;Reachable=$true;State='Connected';Milliseconds=$clock.ElapsedMilliseconds}
    }catch{return [pscustomobject]@{Host=$HostName;Port=$Port;Reachable=$false;State='Failed';Milliseconds=$clock.ElapsedMilliseconds;NativeCode=(Get-PestoNativeFailureCode $_)}}
    finally{if($async){$async.AsyncWaitHandle.Close()};$client.Close();$clock.Stop()}
}
function Get-PestoTransportRequirements {
    param([ValidateSet('Join','Rename','Move','Observe')][string]$Action)
    # Port-specific findings must not identify LDAP as ADWS. A TCP connection
    # observes reachability only, never protocol authentication or write rights.
    $ldap=[pscustomobject]@{Target='DC';Ports=@(389);Note='LDAP (TCP/389) ; connexion TCP seulement, authentification et droits non certifiés.'}
    $adws=[pscustomobject]@{Target='DC';Ports=@(9389);Note='ADWS (TCP/9389) ; connexion TCP seulement, authentification et droits non certifiés.'}
    switch($Action){
        'Join'{@([pscustomobject]@{Target='DC';Ports=@(88);Note='Kerberos TCP ; UDP non certifié par cette connexion.'},$ldap,[pscustomobject]@{Target='DC';Ports=@(445,135);Note='SMB et RPC ; RPC dynamique non certifié par ces connexions TCP.'},$adws)}
        'Rename'{@($ldap,$adws,[pscustomobject]@{Target='Computer';Ports=@(135,445);Note='RPC/DCOM et partage ; les ports dynamiques et droits restent à vérifier par la vraie opération.'})}
        'Move'{@($ldap,$adws)}
        'Observe'{@($ldap,$adws,[pscustomobject]@{Target='Computer';Ports=@(135);Note='WMI/DCOM ; WinRM non exigé.'})}
    }
}
function Get-PestoClockObservation {
    param([Parameter(Mandatory=$true)][string]$DC,[ValidateRange(1000,15000)][int]$TimeoutMilliseconds=6000)
    if(-not(Test-PestoDnsName $DC)){throw 'Contrôleur invalide.'}
    if([Environment]::OSVersion.Platform -ne 'Win32NT'){return New-PestoDiagnosticFinding Clock Unknown 'Mesure Windows non exécutée sur cette plateforme.'}
    $exe=Join-Path $env:SystemRoot 'System32\w32tm.exe'
    if(-not [IO.File]::Exists($exe)){return New-PestoDiagnosticFinding Clock Unknown 'w32tm indisponible.'}
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe
    $start.Arguments='/stripchart /computer:'+ $DC +' /dataonly /samples:1';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try{
        [void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($TimeoutMilliseconds)){try{$process.Kill()}catch{};return New-PestoDiagnosticFinding Clock Unknown 'Mesure expirée ; aucune correction d''horloge exécutée.'}
        $text=$stdout.GetAwaiter().GetResult();$errorText=$stderr.GetAwaiter().GetResult()
        $offset=[regex]::Match($text,'(?m),\s*([+-]\d+(?:[.,]\d+)?)s\s*$')
        if($process.ExitCode -ne 0 -or -not $offset.Success){return New-PestoDiagnosticFinding Clock Unknown ('Mesure non disponible : '+$errorText) @{ExitCode=$process.ExitCode}}
        $seconds=[double]::Parse($offset.Groups[1].Value.Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture)
        New-PestoDiagnosticFinding Clock $(if([Math]::Abs($seconds) -ge 300){'Warning'}else{'Observed'}) 'Écart observé par w32tm ; ni correction ni certification Kerberos.' ([pscustomobject]@{DC=$DC;OffsetSeconds=$seconds;CorrectionApplied=$false})
    }finally{$process.Dispose()}
}
function Get-PestoJoinClockCheck {
    param([string]$DC,$Policy)
    if(-not $Policy.BlockJoinOnClockSkew){return $null}
    try{
        $finding=Get-PestoClockObservation -DC $DC -TimeoutMilliseconds 6000
        $seconds=$finding.Data.OffsetSeconds
        if($finding.State -in @('Observed','Warning') -and ($seconds -is [double] -or $seconds -is [decimal] -or $seconds -is [int]) -and
           -not [double]::IsNaN([double]$seconds) -and -not [double]::IsInfinity([double]$seconds)){
            return [pscustomobject]@{Check='Horloge';State=$(if([Math]::Abs([double]$seconds) -ge 300){'Bloqué'}else{'OK'});
                Detail=('Écart mesuré avec '+$DC+' : '+$seconds+' s. Seuil de blocage : 300 s. Aucune correction automatique.')}
        }
        return [pscustomobject]@{Check='Horloge';State='Avertissement';Detail='Écart non mesuré. La jonction reste possible ; Windows validera l’’authentification.'}
    }catch{return [pscustomobject]@{Check='Horloge';State='Avertissement';Detail='Mesure d’’horloge indisponible. Aucune correction et aucun blocage ajoutés.'}}
}

function Get-PestoRestartReasons {
    $reasons=[Collections.Generic.List[object]]::new()
    if([Environment]::OSVersion.Platform -ne 'Win32NT'){return New-PestoDiagnosticFinding Restart Unknown 'Registre Windows non disponible.'}
    try{
        $active=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName
        $configured=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction Stop).ComputerName
        if($active -ine $configured){$reasons.Add([pscustomobject]@{Reason='ComputerName';Detail='Nom Windows configuré différent du nom actif.';BlocksRename=$true})}
    }catch{$reasons.Add([pscustomobject]@{Reason='UnknownComputerName';Detail='Noms Windows non lisibles.';BlocksRename=$null})}
    foreach($pair in @(@('CBS','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'),@('WindowsUpdate','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))){
        try{if(Test-Path -LiteralPath $pair[1] -ErrorAction Stop){$reasons.Add([pscustomobject]@{Reason=$pair[0];Detail='Windows indique un redémarrage requis.';BlocksRename=$false})}}
        catch{$reasons.Add([pscustomobject]@{Reason=$pair[0];Detail='Indicateur inaccessible.';BlocksRename=$null})}
    }
    try{$pending=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations;if($pending){$reasons.Add([pscustomobject]@{Reason='FileOperations';Detail='Des opérations sur fichiers attendent un démarrage ; aucun chemin exporté.';BlocksRename=$false})}}
    catch [Management.Automation.PSArgumentException]{} catch{$reasons.Add([pscustomobject]@{Reason='FileOperations';Detail='Indicateur non disponible.';BlocksRename=$null})}
    New-PestoDiagnosticFinding Restart Observed 'Indicateurs Windows observés ; absence d''indicateur ne certifie pas l''absence de toute raison de redémarrer.' $reasons.ToArray()
}
function Get-PestoAccountCapability {
    param([ValidateSet('Join','Rename','Move','Observe')][string]$Action,[bool]$ReadSucceeded=$false,$NativeCode=$null)
    $refused=($NativeCode -is [int] -or $NativeCode -is [long]) -and $NativeCode -in @(5,1314,1326)
    [pscustomobject]@{Action=$Action;Read=$(if($ReadSucceeded){'Observed'}elseif($refused){'Refused'}else{'Unknown'});
        Write=$(if($refused){'Refused'}else{'NotCertifiable'});NativeCode=$NativeCode;
        Detail='Une lecture ou une ACL apparente ne certifie pas le droit effectif de mutation. Windows/AD arbitre lors de l''appel réel.'}
}
function ConvertFrom-PestoNetSetupLog {
    param([Parameter(Mandatory=$true)][string[]]$Lines,[Parameter(Mandatory=$true)][DateTimeOffset]$Start,
        [Parameter(Mandatory=$true)][DateTimeOffset]$End,[string[]]$Names=@(),[ValidateRange(1,5000)][int]$MaximumRecords=500,
        [TimeZoneInfo]$LogTimeZone=[TimeZoneInfo]::Local,[string]$OperationId='')
    if($OperationId){$id=[Guid]::Empty;if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de corrélation invalide.'}}
    if($End -lt $Start -or ($End-$Start).TotalDays -gt 7){throw 'Intervalle NetSetup invalide ou supérieur à sept jours.'}
    if($Lines.Count -gt 50000 -or @($Names).Count -gt 8){throw 'Lecture NetSetup trop volumineuse.'}
    foreach($name in $Names){if(-not(Test-PestoComputerName $name)){throw 'Nom de corrélation invalide.'}}
    $rows=[Collections.Generic.List[object]]::new();$nameHits=0;$truncated=$false;$lineNumber=0
    foreach($line in $Lines){
        $lineNumber++;if($line.Length -gt 16384){continue}
        $match=[regex]::Match($line,'^(\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}:\d{3})\s+(.*)$')
        if(-not $match.Success){continue}
        $stamp=[DateTime]::MinValue
        if(-not [DateTime]::TryParseExact($match.Groups[1].Value,'MM/dd/yyyy HH:mm:ss:fff',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$stamp)){continue}
        if($LogTimeZone.IsInvalidTime($stamp) -or $LogTimeZone.IsAmbiguousTime($stamp)){continue}
        $utc=[TimeZoneInfo]::ConvertTimeToUtc([DateTime]::SpecifyKind($stamp,[DateTimeKind]::Unspecified),$LogTimeZone)
        if($utc -lt $Start.UtcDateTime -or $utc -gt $End.UtcDateTime){continue}
        $text=$match.Groups[2].Value;$matchedNames=@(foreach($name in $Names){if($text -match ('(?i)(?<![A-Z0-9-])'+[regex]::Escape($name)+'(?![A-Z0-9-])')){$name}})
        if($matchedNames.Count){$nameHits++}
        $codes=@(foreach($code in [regex]::Matches($text,'(?i)\b0x([0-9a-f]{1,8})\b')){[Convert]::ToInt64($code.Groups[1].Value,16)})
        if($rows.Count -ge $MaximumRecords){$truncated=$true;continue}
        $rows.Add([pscustomobject]@{Line=$lineNumber;Utc=$utc.ToString('o');Names=$matchedNames;NativeCodes=$codes;Text=(Protect-PestoLogText $text)})
    }
    [pscustomobject]@{Schema=1;OperationId=$OperationId;StartUtc=$Start.UtcDateTime.ToString('o');EndUtc=$End.UtcDateTime.ToString('o');Records=$rows.ToArray();NameMatches=$nameHits;Truncated=$truncated;
        Correlation=$(if(-not $Names.Count){'TimeOnly'}elseif($nameHits){'TimeAndName'}else{'Unconfirmed'});ProvesSuccess=$false;
        Notice='Corrélation temporelle et noms, pas preuve d''identité ni de succès. Les lignes concurrentes peuvent partager l''intervalle.'}
}
function Invoke-PestoReadDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Domain,[string]$DC,[string]$Computer,
        [ValidateSet('Join','Rename','Move','Observe')][string]$Action='Observe',
        [ValidateSet('Network','Clock','Account','Restart')][string[]]$Checks=@('Network'),$Credential=$null)
    if(-not(Test-PestoDnsName $Domain)){throw 'Domaine de diagnostic invalide.'}
    if($Computer -and -not(Test-PestoComputerName $Computer)){throw 'Nom de poste invalide.'}
    $findings=[Collections.Generic.List[object]]::new();$chosen=$DC
    if(-not $chosen){try{$chosen=Get-DomainController $Domain}catch{$findings.Add((New-PestoDiagnosticFinding Controller Unknown $_.Exception.Message))}}
    if($chosen -and (-not(Test-PestoDnsName $chosen) -or $chosen.IndexOf('.') -lt 1 -or $chosen -ieq $Domain)){throw 'DC FQDN invalide ; aucun autre DC essayé.'}
    if('Network' -in $Checks){
        try{$ip=[Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties();$findings.Add((New-PestoDiagnosticFinding DnsSuffix Observed 'Suffixe local observé.' ([pscustomobject]@{Suffix=$ip.DomainName;ExpectedDomain=$Domain})))}catch{$findings.Add((New-PestoDiagnosticFinding DnsSuffix Unknown $_.Exception.Message))}
        if(Get-Command Resolve-DnsName -ErrorAction SilentlyContinue){
            try{$srv=@(Resolve-DnsName -Name ('_ldap._tcp.dc._msdcs.'+$Domain) -Type SRV -DnsOnly -QuickTimeout -ErrorAction Stop|Where-Object Type -eq SRV|Select-Object -First 128 NameTarget,Port,Priority,Weight);$findings.Add((New-PestoDiagnosticFinding DnsSrv Observed 'Enregistrements SRV observés ; aucun contrôleur remplacé.' $srv))}
            catch{$findings.Add((New-PestoDiagnosticFinding DnsSrv Unknown $_.Exception.Message))}
        }else{$findings.Add((New-PestoDiagnosticFinding DnsSrv Unknown 'Resolve-DnsName indisponible.'))}
        if($chosen){
            $findings.Add((New-PestoDiagnosticFinding Controller Observed 'Contrôleur fourni par la session ou découvert par Windows, sans bascule.' @{DC=$chosen}))
            foreach($requirement in @(Get-PestoTransportRequirements $Action)){
                $hostName=if($requirement.Target -eq 'DC'){$chosen}else{$Computer}
                if(-not $hostName){continue}
                foreach($port in $requirement.Ports){$probe=Test-PestoDiagnosticEndpoint -HostName $hostName -Port $port;$findings.Add((New-PestoDiagnosticFinding ('TCP.'+$port) $(if($probe.Reachable){'Observed'}else{'Warning'}) $requirement.Note $probe))}
            }
        }
        $findings.Add((New-PestoDiagnosticFinding Ping Unknown 'ICMP est indicatif ; aucun refus de mutation déduit du ping.'))
    }
    if('Clock' -in $Checks){if($chosen){$findings.Add((Get-PestoClockObservation $chosen))}else{$findings.Add((New-PestoDiagnosticFinding Clock Unknown 'Contrôleur inconnu.'))}}
    if('Restart' -in $Checks){$findings.Add((Get-PestoRestartReasons))}
    if('Account' -in $Checks){
        if($chosen -and $Computer){
            try{
                $adp=@{Server=$chosen;ErrorAction='Stop'};if($Credential){$adp.Credential=$Credential}
                $pc=Get-ADComputer -Identity $Computer -Properties DNSHostName,ServicePrincipalName,Enabled @adp
                $spns=@($pc.ServicePrincipalName);$fqdn=$Computer+'.'+$Domain
                $data=[pscustomobject]@{Name=$pc.Name;Guid=[string]$pc.ObjectGUID;Enabled=[bool]$pc.Enabled;DNSHostName=[string]$pc.DNSHostName;SPNCount=$spns.Count;
                    DnsMatches=([string]$pc.DNSHostName -ieq $fqdn);HostSpnPresent=(@($spns|Where-Object{$_ -ieq ('HOST/'+$fqdn) -or $_ -ieq ('HOST/'+$Computer)}).Count -gt 0)}
                $findings.Add((New-PestoDiagnosticFinding Account $(if($data.DnsMatches -and $data.HostSpnPresent){'Observed'}else{'Warning'}) 'Objet AD observé, sans suppression ni correction DNS/SPN.' $data))
                $findings.Add((New-PestoDiagnosticFinding Capabilities Observed 'Capacité de lecture distincte des droits d''écriture.' (Get-PestoAccountCapability -Action $Action -ReadSucceeded $true)))
            }catch{$findings.Add((New-PestoDiagnosticFinding Account Unknown $_.Exception.Message));$findings.Add((New-PestoDiagnosticFinding Capabilities Unknown 'Aucune capacité d''écriture certifiée.' (Get-PestoAccountCapability -Action $Action -NativeCode (Get-PestoNativeFailureCode $_))))}
        }else{$findings.Add((New-PestoDiagnosticFinding Account Unknown 'Nom du poste et contrôleur explicite requis.'))}
        $findings.Add((New-PestoDiagnosticFinding Entra Unknown 'L''état Entra exige une observation distincte du poste ; AD ne prouve pas une réinscription Entra.'))
        $findings.Add((New-PestoDiagnosticFinding NetjoinReuse Unknown 'La présence du compte ne certifie pas sa réutilisation. Windows applique les règles Netjoin ; erreur 2732 à corréler au journal NetSetup.'))
    }
    [pscustomobject]@{PSTypeName='Pesto.Diagnostic.Report';Schema=1;Domain=$Domain;DC=$chosen;Action=$Action;ReadOnly=$true;MutationAuthorized=$false;Findings=$findings.ToArray()}
}

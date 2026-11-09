#requires -Version 5.1
# Compatibilité : les clés de stockage/verrous GP sont stables ; ne pas les renommer ni les effacer. Voir docs/RENOMMAGE_PESTO.md (DEV).
[CmdletBinding()]
param(
    [switch]$Demo,
    [switch]$Consult,
    [switch]$DemoJoin,
    [switch]$AskCredential,
    [switch]$CheckPackage,
    [switch]$QuietCheck,
    [string]$CheckReportPath,
    [string]$PlanInputPath,
    [string]$ConfigPath,
    [switch]$ElevatedLaunch,
    [string]$OriginLocalAppData,
    [string]$AppearanceOwnerSid,
    [string]$UacProbe
)
# Pesto 1.0 : point d'entrée PowerShell interne à wad.
# Chargé avec '. fichier', ce composant définit seulement ses fonctions.

function Get-PestoStartupIdentity {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try { return [pscustomobject]@{Name=$identity.Name;Sid=$identity.User.Value} }
    finally { $identity.Dispose() }
}

function Test-PestoStartupAdministrator {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=[Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } finally { $identity.Dispose() }
}

function Get-PestoStartupRoute {
    param([bool]$Demo,[bool]$IsAdministrator,[bool]$ElevatedLaunch)
    if($Demo){return 'Demo'}
    if($IsAdministrator){return 'Run'}
    # Le marqueur interdit une boucle ; il ne remplace jamais le controle du jeton.
    if($ElevatedLaunch){return 'Refuse'}
    return 'Elevate'
}

function ConvertTo-PestoStartupArgument {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Value)
    if($Value -match '[\x00-\x1f\x7f"]'){throw 'Argument de démarrage invalide.'}
    # Regle Win32 : doubler les antislashs avant le guillemet fermant.
    # Les autres caracteres restent des donnees : aucun cmd.exe / -Command.
    $quoted=[regex]::Replace($Value,'(\\+)$','$1$1')
    return ('"'+$quoted+'"')
}

function Resolve-PestoStartupUacProbe {
    # Sonde de VERIFIER_UAC.cmd : jeton aléatoire de 32 hex minuscules, jamais un chemin ni une commande.
    # Processus non élevé : -UacProbe, sinon PESTO_UAC_PROBE héritée de Pesto.exe (lanceur et empreintes inchangés).
    # Relais élevé : -UacProbe seulement ; l'environnement ne franchit pas l'UAC et n'y est jamais relu.
    # Une valeur invalide arrête le démarrage : jamais ignorée, donc jamais le vrai moteur à la place de la sonde.
    param([string]$Parameter,[bool]$ParameterBound,[string]$Environment,[bool]$ElevatedLaunch)
    $value=if($ParameterBound -or $ElevatedLaunch){$Parameter}else{$Environment}
    if(-not $ParameterBound -and [string]::IsNullOrEmpty($value)){return ''}
    if($value -cnotmatch '^[0-9a-f]{32}\z'){throw 'Sonde UAC invalide (PESTO_UAC_PROBE ou -UacProbe) : 32 caractères hexadécimaux minuscules attendus. Aucune UAC demandée, aucun moteur chargé.'}
    return $value
}

function Show-PestoStartupProbeMessage {
    param([string]$Text,[bool]$Success)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [void][Windows.MessageBox]::Show($Text,'Pesto - sonde UAC (aucun moteur chargé)','OK',$(if($Success){'Information'}else{'Error'}))
    } catch { Write-Host $Text }
}

function Complete-PestoStartupUacProbe {
    # Fin de la sonde, avant la reprise d'état, le mutex de session et Pesto-Core : aucun moteur, aucun AD.
    # Seul effet : un reçu CreateNew dans wad\logs (chemin fixe, liens refusés) et une ligne du journal de démarrage.
    # Codes : 0 = relais élevé avec jeton administrateur ; 2 = sonde non concluante ; 3 = relais élevé, reçu non écrit.
    param([string]$Root,[string]$Probe,[string]$Route,[bool]$IsAdministrator,[bool]$ElevatedLaunch,[string]$Account)
    if($Probe -cnotmatch '^[0-9a-f]{32}\z'){throw 'Sonde UAC invalide.'}
    $result=if($ElevatedLaunch -and $IsAdministrator -and $Route -eq 'Run'){'UAC_OK'}elseif($ElevatedLaunch){'RELAIS_SANS_ADMIN'}else{'DEJA_ADMIN_SANS_UAC'}
    $lines=@('Pesto - sonde UAC (VERIFIER_UAC.cmd)',('Sonde='+$Probe),('Resultat='+$result),('Admin='+$IsAdministrator),('RelaisEleve='+$ElevatedLaunch),
        ('Route='+$Route),('Compte='+$Account),('PID='+$PID),('UTC='+[DateTime]::UtcNow.ToString('o')),'Moteur=NON_CHARGE','RepriseEtat=NON_FAITE','AD=NON_CONTACTE')
    $relative='wad\logs\Pesto-sonde-uac-'+$Probe+'.txt'
    $path=Join-Path $Root $relative
    $written=$false
    try {
        $directory=[IO.Path]::GetDirectoryName($path)
        Assert-PestoStartupLocalPath $directory
        [void][IO.Directory]::CreateDirectory($directory)
        Write-PestoStartupNewFile -Path $path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`r`n")+"`r`n"))
        $written=$true
    } catch { Write-PestoStartupLog -Root $Root -Message ('Sonde UAC : reçu non écrit ('+$_.Exception.Message+').') }
    Write-PestoStartupLog -Root $Root -Message ('Sonde UAC '+$Probe+' : '+$result+' Admin='+$IsAdministrator+'. Moteur non charge, aucune reprise d''etat.')
    $code=if($result -ne 'UAC_OK'){2}elseif($written){0}else{3}
    $text="Sonde UAC : $result`r`nJeton administrateur : $IsAdministrator`r`nRelais élevé : $ElevatedLaunch`r`nCompte Windows : $Account`r`n`r`nAucun moteur chargé, aucune reprise d'état, aucune connexion AD.`r`n"
    
    $logInfo = if ($script:PestoStartupLogPath) { 
        'Journal : ' + $script:PestoStartupLogPath 
    } else { 
        'Journal : non écrit (inaccessible)' 
    }
    
    $text+=$(if($written){'Reçu : '+$relative+"`r`n"+$logInfo}else{'Reçu non écrit : '+$logInfo})
    Show-PestoStartupProbeMessage -Text $text -Success ($code -eq 0)
    return $code
}

function New-PestoStartupArgumentLine {
    param([string]$EntryPath,[string]$ConfigPath,[string]$OriginLocalAppData,[switch]$AskCredential,[string]$AppearanceOwnerSid,[string]$UacProbe)
    $parts=[Collections.Generic.List[string]]::new()
    if([IO.Path]::GetExtension($EntryPath) -ieq '.ps1'){
        foreach($arg in @('-NoLogo','-NoProfile','-STA','-WindowStyle','Hidden','-ExecutionPolicy','RemoteSigned','-File')){$parts.Add($arg)}
        $parts.Add((ConvertTo-PestoStartupArgument $EntryPath))
    } elseif([IO.Path]::GetExtension($EntryPath) -ine '.exe'){
        throw 'Le point d''entrée doit être Pesto-Startup.ps1 ou Pesto.exe.'
    }
    $parts.Add('-ElevatedLaunch')
    if($AskCredential){$parts.Add('-AskCredential')}
    if($ConfigPath){$parts.Add('-ConfigPath');$parts.Add((ConvertTo-PestoStartupArgument $ConfigPath))}
    if($OriginLocalAppData){$parts.Add('-OriginLocalAppData');$parts.Add((ConvertTo-PestoStartupArgument $OriginLocalAppData))}
    if($AppearanceOwnerSid){
        if($AppearanceOwnerSid -notmatch '^S-1-\d+(?:-\d+){1,14}$'){throw 'SID de préférence invalide.'}
        $parts.Add('-AppearanceOwnerSid');$parts.Add((ConvertTo-PestoStartupArgument $AppearanceOwnerSid))
    }
    if($UacProbe){
        if($UacProbe -cnotmatch '^[0-9a-f]{32}\z'){throw 'Sonde UAC invalide.'}
        $parts.Add('-UacProbe');$parts.Add((ConvertTo-PestoStartupArgument $UacProbe))
    }
    return ($parts -join ' ')
}

function Test-PestoStartupCancellation {
    param([AllowNull()]$Exception)
    for($i=0;$Exception -and $i -lt 8;$i++){
        if($Exception -is [ComponentModel.Win32Exception] -and $Exception.NativeErrorCode -eq 1223){return $true}
        $Exception=$Exception.InnerException
    }
    return $false
}

function Write-PestoStartupLog {
    param([string]$Root,[string]$Message)
    # Aucun identifiant secret ou argument de commande n'est journalise.
    # Ne leve jamais : un journal indisponible ne doit pas faire refuser le demarrage.
    try {
        $line='{0} [startup] PID={1} {2}' -f [DateTime]::Now.ToString('s'),$PID,($Message -replace '[\r\n]+',' ')

        # Liste des chemins candidats : Racine, LocalAppData, Temp (variables absentes en SYSTEM ou service)
        $candidates = @()
        if ($Root) { $candidates += (Join-Path $Root 'wad\logs') }
        $localAppData = $env:LOCALAPPDATA
        if (-not $localAppData) { try { $localAppData = [Environment]::GetFolderPath('LocalApplicationData') } catch {} }
        if ($localAppData) { $candidates += (Join-Path $localAppData 'Pesto\logs') }
        $tempDir = $env:TEMP
        if (-not $tempDir) { try { $tempDir = [IO.Path]::GetTempPath() } catch {} }
        if ($tempDir) { $candidates += (Join-Path $tempDir 'Pesto\logs') }

        $success = $false
        $lastError = $null
        $usedPath = $null

        foreach ($dir in $candidates) {
            try {
                if (-not [IO.Directory]::Exists($dir)) {
                    [void][IO.Directory]::CreateDirectory($dir)
                }
                $logFile = Join-Path $dir 'Pesto-demarrage.log'
                Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction Stop
                $success = $true
                $usedPath = $logFile
                break
            } catch {
                $lastError = $_.Exception.Message
            }
        }

        if ($success) {
            $script:PestoStartupLogPath = $usedPath
        } else {
            Write-Warning ('Le journal de démarrage est inaccessible. Dernier essai : ' + $lastError + '. Le contrôle UAC reste obligatoire.')
        }
    } catch {}
}

function Start-PestoStartupProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    return [Diagnostics.Process]::Start($StartInfo)
}

function Invoke-PestoStartupElevation {
    param([string]$EntryPath,[string]$ConfigPath,[string]$OriginLocalAppData,[string]$Root,[switch]$AskCredential,[string]$AppearanceOwnerSid,[string]$UacProbe)
    $line=New-PestoStartupArgumentLine -EntryPath $EntryPath -ConfigPath $ConfigPath -OriginLocalAppData $OriginLocalAppData -AskCredential:$AskCredential -AppearanceOwnerSid $AppearanceOwnerSid -UacProbe $UacProbe
    $exe=if([IO.Path]::GetExtension($EntryPath) -ieq '.exe'){$EntryPath}else{Join-Path $PSHOME 'powershell.exe'}
    if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "Lanceur Windows introuvable : $exe"}
    $process=$null
    try {
        Write-PestoStartupLog -Root $Root -Message 'Autorisation UAC demandee AVANT le chargement du moteur et du login.'
        # Pas de -Credential : Windows gere sa propre demande UAC sur le bureau securise.
        # Le dossier systeme evite les problemes de WorkingDirectory avec [] dans le projet.
        # Windows PowerShell 5.1 Start-Process perd le NativeErrorCode lors du refus UAC.
        # Process.Start conserve Win32Exception (1223), même sous l'enveloppe MethodInvocationException.
        $info=[Diagnostics.ProcessStartInfo]::new($exe)
        $info.UseShellExecute=$true
        $info.Verb='RunAs'
        $info.Arguments=$line
        $info.WorkingDirectory=$env:SystemRoot
        $process=Start-PestoStartupProcess -StartInfo $info
        if($null -eq $process){throw 'Windows n''a retourne aucun processus eleve.'}
        [void]$process.Handle
        Write-PestoStartupLog -Root $Root -Message ('Relais lance, PID='+$process.Id+'. Le parent ne charge pas Pesto-Core.')
        $process.WaitForExit()
        $process.Refresh()
        if($null -eq $process.ExitCode){throw 'Le code de sortie du relais est indisponible.'}
        return [int]$process.ExitCode
    } catch {
        if(Test-PestoStartupCancellation $_.Exception){
            Write-PestoStartupLog -Root $Root -Message 'UAC annulée. Aucun moteur chargé, aucune action lancée.'
            return 1223
        }
        throw
    } finally { if($process){$process.Dispose()} }
}

function Get-PestoStartupStateId {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $full=[IO.Path]::GetFullPath($ConfigPath).ToLowerInvariant()
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($full)))).Replace('-','').Substring(0,16) }
    finally { $sha.Dispose() }
}

function Assert-PestoStartupLocalPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path -match '[\x00-\x1f\x7f"]'){
        throw 'Le dossier de reprise doit être un chemin local absolu.'
    }
    # Ne jamais suivre une jonction/lien en copiant un etat depuis un autre profil.
    $p=[IO.Path]::GetFullPath($Path)
    while($p){
        if(Test-Path -LiteralPath $p){
            $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Lien/jonction non autorisé pour la reprise : $p"}
        }
        $parent=[IO.Path]::GetDirectoryName($p)
        if($parent -eq $p){break};$p=$parent
    }
}

function Read-PestoStartupStateFile {
    param([Parameter(Mandatory=$true)][string]$Path,[long]$MaxBytes=16777216)
    Assert-PestoStartupLocalPath $Path
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -gt $MaxBytes){throw 'Fichier de reprise trop volumineux.'}
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while($offset -lt $bytes.Length){
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($read -eq 0){throw 'Lecture de reprise incomplete.'}
            $offset+=$read
        }
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
        finally { $sha.Dispose() }
        return [pscustomobject]@{Bytes=$bytes;Hash=$hash}
    } finally { $stream.Dispose() }
}

function Write-PestoStartupNewFile {
    param([string]$Path,[byte[]]$Bytes)
    Assert-PestoStartupLocalPath $Path
    # CreateNew : ne remplace jamais un fichier de reprise deja present.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true) }
    catch {
        $stream.Dispose();$stream=$null
        try{[IO.File]::Delete($Path)}catch{}
        throw
    } finally { if($stream){$stream.Dispose()} }
}

function Test-PestoStartupEmptyQueues {
    param([byte[]]$OriginBytes,[byte[]]$CurrentBytes)
    # Seules deux files REEL Idle explicitement vides peuvent différer sans conflit.
    # Aucun fichier n'est remplacé ; un champ inconnu peut être un verrou futur.
    try {
        $queues=@(foreach($bytes in @($OriginBytes,$CurrentBytes)){
            $text=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)
            $q=$text|ConvertFrom-Json -ErrorAction Stop
            if(-not $q -or $q.Schema -isnot [int] -or $q.Schema -ne 1 -or
               $q.Phase -cne 'Idle' -or $q.Mode -cne 'REEL' -or
               $q.Rows -isnot [Array] -or $q.Rows.Count -ne 0 -or
               $q.OperationIds -isnot [Array] -or $q.OperationIds.Count -ne 0 -or
               $q.Domain -isnot [string] -or [string]::IsNullOrWhiteSpace($q.Domain) -or
               $q.MachineId -isnot [string]){return $false}
            foreach($property in $q.PSObject.Properties){
                if($property.Name -notin @('Schema','Version','Domain','Host','MachineId','Mode','Phase','Utc','OperationIds','Rows')){return $false}
            }
            $guid=[Guid]::Empty
            if(-not [Guid]::TryParse($q.MachineId,[ref]$guid) -or $guid -eq [Guid]::Empty){return $false}
            $q
        })
        return ($queues.Count -eq 2 -and $queues[0].Domain -ieq $queues[1].Domain -and
                $queues[0].MachineId -ieq $queues[1].MachineId)
    }catch{return $false}
}

function Test-PestoStartupHistoryPair {
    param([byte[]]$OriginBytes,[byte[]]$CurrentBytes)
    # Historique de synthèses uniquement : jamais une source de reprise ou de verrous.
    # Les deux fichiers restent intacts ; l'original est aussi archivé par son empreinte.
    try {
        $histories=@(foreach($bytes in @($OriginBytes,$CurrentBytes)){
            if($bytes.Length -gt 2097152){return $false}
            $h=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)|ConvertFrom-Json -ErrorAction Stop
            if(-not $h -or $h.Schema -isnot [int] -or $h.Schema -ne 1 -or
               $h.Domain -isnot [string] -or [string]::IsNullOrWhiteSpace($h.Domain) -or
               $h.Entries -isnot [Array] -or $h.Entries.Count -gt 100){return $false}
            foreach($p in $h.PSObject.Properties){if($p.Name -notin @('Schema','Domain','Entries')){return $false}}
            foreach($entry in $h.Entries){
                if(-not $entry){return $false}
                foreach($p in $entry.PSObject.Properties){if($p.Name -notin @('RunId','Mode','Utc','Total','Ok','Failed','NotStarted','Locked')){return $false}}
                $id=[Guid]::Empty;$utc=[DateTimeOffset]::MinValue
                if($entry.RunId -isnot [string] -or -not [Guid]::TryParse($entry.RunId,[ref]$id) -or $id -eq [Guid]::Empty -or
                   $entry.Utc -isnot [string] -or -not [DateTimeOffset]::TryParse($entry.Utc,[ref]$utc) -or
                   $entry.Mode -isnot [string] -or $entry.Mode.Length -gt 64 -or $entry.Mode -match '[\x00-\x1f\x7f]' -or
                   $entry.Locked -isnot [bool]){return $false}
                foreach($field in @('Total','Ok','Failed','NotStarted')){if($entry.$field -isnot [int] -or $entry.$field -lt 0){return $false}}
            }
            $h
        })
        return ($histories.Count -eq 2 -and $histories[0].Domain -ieq $histories[1].Domain)
    }catch{return $false}
}

function Import-PestoStartupState {
    param([string]$OriginLocalAppData,[string]$CurrentLocalAppData,[string]$ConfigPath,[string]$Root)
    if(-not $OriginLocalAppData){return}
    $origin=[IO.Path]::GetFullPath($OriginLocalAppData).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $current=[IO.Path]::GetFullPath($CurrentLocalAppData).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if($origin -ieq $current){return}
    Assert-PestoStartupLocalPath $origin;Assert-PestoStartupLocalPath $current
    $id=Get-PestoStartupStateId $ConfigPath
    $source=Join-Path $origin ('GP\State\'+$id)
    if(-not(Test-Path -LiteralPath $source -PathType Container)){return}
    Assert-PestoStartupLocalPath $source
    $destination=Join-Path $current ('GP\State\'+$id)
    Assert-PestoStartupLocalPath $destination
    [void][IO.Directory]::CreateDirectory($destination)
    # Un recu par fichier et empreinte : un ancien checkpoint deja traite ne revient pas.
    # Si l'ancienne instance ecrit un nouvel etat, son empreinte change et il est recontrole.
    foreach($name in @('queue.json','history-v1.json')){
        $src=Join-Path $source $name
        if(-not(Test-Path -LiteralPath $src -PathType Leaf)){continue}
        $data=Read-PestoStartupStateFile $src
        $receipt=Join-Path $destination ('.startup-import-'+$name+'-'+$data.Hash+'.txt')
        if(Test-Path -LiteralPath $receipt -PathType Leaf){
            Assert-PestoStartupLocalPath $receipt
            continue
        }
        $dst=Join-Path $destination $name
        if(Test-Path -LiteralPath $dst -PathType Leaf){
            $existing=Read-PestoStartupStateFile $dst
            if($existing.Hash -ne $data.Hash){
                if($name -eq 'history-v1.json' -and (Test-PestoStartupHistoryPair $data.Bytes $existing.Bytes)){
                    $archive=Join-Path $destination ('history-imported-'+$data.Hash+'.json')
                    if(Test-Path -LiteralPath $archive -PathType Leaf){
                        if((Read-PestoStartupStateFile $archive).Hash -ne $data.Hash){throw 'Archive historique differente : aucun remplacement.'}
                    }else{Write-PestoStartupNewFile -Path $archive -Bytes $data.Bytes}
                    Write-PestoStartupLog -Root $Root -Message ("Historique de l'autre profil archive sans fusion : $archive. Historique courant et originaux conserves ; aucun verrou resolu.")
                }elseif(-not ($name -eq 'queue.json' -and (Test-PestoStartupEmptyQueues $data.Bytes $existing.Bytes))){
                    # On ne choisit jamais silencieusement entre deux files / deux verrous.
                    throw "Reprise entre comptes en conflit ($name). Aucun fichier ecrase. Ancien etat : $src ; etat administrateur : $dst. Fermez les autres instances et faites examiner ces deux fichiers avant de relancer."
                }
            }
        } else { Write-PestoStartupNewFile -Path $dst -Bytes $data.Bytes }
        $note=[Text.Encoding]::UTF8.GetBytes(('Reprise examinee sans relance automatique ; fichiers existants preserves. UTC='+[DateTime]::UtcNow.ToString('o')))
        Write-PestoStartupNewFile -Path $receipt -Bytes $note
        Write-PestoStartupLog -Root $Root -Message ("Etat $name examine pour le profil eleve ; fichiers existants conserves. Les verrous restent dans le checkpoint.")
    }
}

function Get-PestoStartupLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$StartupPath)
    # La racine vient du composant exécuté, jamais du dossier courant ou de PowerShell.
    $entry=[IO.Path]::GetFullPath($StartupPath)
    if([IO.Path]::GetFileName($entry) -ine 'Pesto-Startup.ps1'){throw 'Point de démarrage Pesto inattendu.'}
    $wad=[IO.Path]::GetDirectoryName($entry)
    if([IO.Path]::GetFileName($wad) -ine 'wad'){throw 'Pesto-Startup.ps1 doit être dans le dossier wad.'}
    $root=[IO.Path]::GetDirectoryName($wad)
    if([string]::IsNullOrWhiteSpace($root)){throw 'Racine de Pesto introuvable.'}
    [pscustomobject]@{
        Root=$root;EntryPath=$entry;Wad=$wad
        CorePath=Join-Path $wad 'Pesto-Core.ps1'
        IntegrityPath=Join-Path $wad 'Pesto-Integrity.ps1'
        LauncherPath=Join-Path $root 'Pesto.exe'
        LogDirectory=Join-Path $wad 'logs'
    }
}

# Ne jamais demander l'UAC ni charger le moteur lors d'un import de fonctions.
if($MyInvocation.InvocationName -eq '.') { return }

$ErrorActionPreference='Stop'
if($DemoJoin){$Demo=$true}
$sessionMutex=$null;$sessionOwned=$false
$root=$null
try {
    if($env:OS -ne 'Windows_NT'){throw 'Pesto necessite Windows PowerShell 5.1 x64 sous Windows.'}
    if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Utiliser Windows PowerShell 5.1 (powershell.exe), pas pwsh.'}
    if(-not [Environment]::Is64BitProcess){throw 'Un processus PowerShell 64 bits est requis. Utiliser Pesto.exe.'}
    if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Un thread STA est requis. Utiliser Pesto.exe ou powershell.exe -STA.'}

    $layout=Get-PestoStartupLayout -StartupPath $PSCommandPath
    $entry=$layout.EntryPath
    $root=$layout.Root
    $core=$layout.CorePath
    $startup=$entry
    foreach($path in @($core,$startup)){
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Fichier absent : $path. Extraire tous les fichiers de la mise a jour, pas seulement Pesto-Core.ps1."}
    }
    $integrity=$layout.IntegrityPath
    if(-not(Test-Path -LiteralPath $integrity -PathType Leaf)){throw 'Module de contrôle du pack absent.'}
    . $integrity
    $package=Test-PestoPackage -Root $root
    $runtime=Test-PestoRuntimeReady -Root $root
    $probe=Resolve-PestoStartupUacProbe -Parameter $UacProbe -ParameterBound ($PSBoundParameters.ContainsKey('UacProbe')) -Environment $env:PESTO_UAC_PROBE -ElevatedLaunch $ElevatedLaunch.IsPresent
    if($CheckPackage){
        $summary='Pesto '+$package.Version+' : '+$package.FileCount+' composants applicatifs cohérents, '+$runtime.ParsedFiles+' scripts et '+$runtime.EmbeddedScripts+' scripts embarqués analysés, journal d''audit compilé. Aucun accès AD ni demande UAC. Démos et tests exclus ; configuration non validée.'
        if($PlanInputPath){
            if(-not $CheckReportPath){throw 'Chemin du rapport de validation requis.'}
            . (Join-Path $layout.Wad 'Pesto-Contracts.ps1')
            $f=Get-Item -LiteralPath $PlanInputPath -Force -ErrorAction Stop
            if($f.PSIsContainer -or $f.Length -gt 65536 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Brouillon absent, lié ou trop volumineux.'}
            $valid=$false;$failure='';$errorCode=0
            try{[void](ConvertTo-PestoDraft ([IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop));$valid=$true}catch{$failure='INVALID_DRAFT';$errorCode=20}
            $r=[ordered]@{Schema=1;Product='Pesto';Version=$package.Version;ValidDraft=$valid;Authorized=$false;Error=$failure;AD='NOT_CONTACTED';UAC='NOT_REQUESTED';Configuration='NOT_VALIDATED'}
            $path=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CheckReportPath)
            $bytes=[Text.Encoding]::UTF8.GetBytes(($r|ConvertTo-Json -Depth 4));$stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
            exit $errorCode
        }
        if($CheckReportPath){
            $report=[ordered]@{Schema=1;Product='Pesto';Version=$package.Version;Runtime='PASS';ComponentCount=$package.FileCount;
                Syntax='PASS';ParsedFiles=$runtime.ParsedFiles;EmbeddedScripts=$runtime.EmbeddedScripts;AuditWriter=$runtime.AuditWriter;
                Platform=[Environment]::OSVersion.Version.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();Architecture='x64';
                Configuration='NOT_VALIDATED';Network='NOT_TESTED';UAC='NOT_REQUESTED';Signature='NOT_ASSERTED';Utc=[DateTime]::UtcNow.ToString('o')}
            # VERIFIER_UAC.cmd exige cet écho avant toute UAC : la sonde a bien traversé ce Pesto.exe.
            if($probe){$report['UacProbe']=$probe}
            $reportFull=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CheckReportPath)
            $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Depth 4))
            # Choix explicite du chemin ; jamais d'écrasement d'un fichier existant.
            $stream=[IO.File]::Open($reportFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        }
        if(-not $QuietCheck){
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            [void][Windows.MessageBox]::Show($summary,'Pesto - Contrôle du pack','OK','Information')
        }
        exit 0
    }
    if($Demo -and -not(Test-Path -LiteralPath (Join-Path $root 'wad\cfg.demo.json') -PathType Leaf)){
        throw 'Démonstration non incluse dans ce dossier. Utiliser le pack DEV pour les aperçus. Aucun accès AD ni demande UAC.'
    }
    if($probe -and ($Demo -or $Consult)){throw 'Sonde UAC refusée avec une démonstration ou --consult : ces modes ne demandent pas l''UAC. Aucun moteur chargé.'}

    # ConfigPath relatif est resolu dans le processus appelant, avant l'UAC.
    $parameters=@{Demo=$Demo.IsPresent;DemoJoin=$DemoJoin.IsPresent;AskCredential=$AskCredential.IsPresent;Consult=$Consult.IsPresent}
    if($PSBoundParameters.ContainsKey('ConfigPath')){
        if([string]::IsNullOrWhiteSpace($ConfigPath)){throw 'Le paramètre ConfigPath ne peut pas être vide.'}
        $parameters.ConfigPath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigPath)
    }
    $isAdmin=Test-PestoStartupAdministrator
    $route=if($Consult -and -not $Demo){'Consult'}else{Get-PestoStartupRoute -Demo $Demo.IsPresent -IsAdministrator $isAdmin -ElevatedLaunch $ElevatedLaunch.IsPresent}
    $identity=Get-PestoStartupIdentity
    if(-not $AppearanceOwnerSid){$AppearanceOwnerSid=$identity.Sid}
    if($AppearanceOwnerSid -notmatch '^S-1-\d+(?:-\d+){1,14}$'){throw 'Identité de préférences invalide.'}
    $parameters.AppearanceOwnerSid=$AppearanceOwnerSid
    Write-PestoStartupLog -Root $root -Message ("Route=$route Admin=$isAdmin Identite=$($identity.Name)")

    if($probe -and $route -ne 'Elevate'){
        # Sonde : arrêt ici, quel que soit le jeton, avant la reprise d'état, le mutex de session et le moteur.
        exit (Complete-PestoStartupUacProbe -Root $root -Probe $probe -Route $route -IsAdministrator $isAdmin -ElevatedLaunch $ElevatedLaunch.IsPresent -Account $identity.Name)
    }
    if($route -eq 'Refuse'){
        throw 'Le relais Windows ne dispose pas d''un jeton administrateur. Pesto s''arrete avant la connexion ; aucune nouvelle demande UAC en boucle.'
    }
    if($route -eq 'Elevate'){
        # Aucun credential Pesto n'existe encore : rien de secret a faire transiter.
        $origin=[Environment]::GetFolderPath('LocalApplicationData')
        if([string]::IsNullOrWhiteSpace($origin)){throw 'Profil de depart indisponible : reprise de file non garantie.'}
        if($probe){Write-PestoStartupLog -Root $root -Message ('Sonde UAC '+$probe+' : relais demande ; il s''arretera avant la reprise d''etat et le moteur.')}
        $exitCode=Invoke-PestoStartupElevation -EntryPath $entry -ConfigPath $parameters.ConfigPath -OriginLocalAppData $origin -Root $root -AskCredential:$AskCredential -AppearanceOwnerSid $AppearanceOwnerSid -UacProbe $probe
        exit $exitCode
    }
    if($route -eq 'Run'){
        if(-not (Test-PestoStartupAdministrator)){throw 'Jeton administrateur indisponible avant le chargement du moteur.'}
        if($ElevatedLaunch){
            if([string]::IsNullOrWhiteSpace($OriginLocalAppData)){throw 'Profil de depart absent du relais : reprise de file non garantie.'}
            $stateConfig=if($parameters.ConfigPath){$parameters.ConfigPath}else{Join-Path $root 'wad\cfg.json'}
            $current=[Environment]::GetFolderPath('LocalApplicationData')
            if([string]::IsNullOrWhiteSpace($current)){throw 'Profil administrateur indisponible.'}
            Import-PestoStartupState -OriginLocalAppData $OriginLocalAppData -CurrentLocalAppData $current -ConfigPath $stateConfig -Root $root
        }
        Write-PestoStartupLog -Root $root -Message 'Admin=True confirme. Chargement du moteur dans CE processus eleve ; compte Windows reutilise automatiquement dans le domaine.'
    } elseif($route -eq 'Consult'){
        $env:PESTO_READONLY_SESSION='1'
        Write-PestoStartupLog -Root $root -Message 'Consultation : aucune elevation demandee, moteur en lecture seule.'
    } else {
        Write-PestoStartupLog -Root $root -Message 'Démo : sans demande UAC, sans connexion AD ni opération réelle.'
    }
    # Le parent non eleve n'atteint jamais ce point en lancement normal.
    # Une instance par dossier et par mode ; aucun mot de passe ni nom de compte
    # n'entre dans le nom de mutex. L'UAC a déjà été réglée à cette étape.
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$sessionId=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()+[string]$Demo.IsPresent)))).Replace('-','').Substring(0,24)}finally{$sha.Dispose()}
    $sessionMutex=[Threading.Mutex]::new($false,('Global\GP_Session_'+$sessionId))
    try{$sessionOwned=$sessionMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$sessionOwned=$true}
    if(-not $sessionOwned){throw 'Pesto est déjà ouvert depuis ce dossier. Revenez à la fenêtre existante ; aucune seconde instance lancée.'}
    & $core @parameters
    exit $LASTEXITCODE
} catch {
    if($QuietCheck){Write-Error -Message $_.Exception.Message -ErrorAction Continue;exit 1}
    # Journaliser d'abord : le message cite ensuite le fichier réellement écrit (racine ou repli).
    if($root){
        try { Write-PestoStartupLog -Root $root -Message ('ERROR '+$_.Exception.Message) } catch {}
    }
    $logHint=if($script:PestoStartupLogPath){$script:PestoStartupLogPath}else{'journal de démarrage non écrit'}
    $message="Pesto n'a pas pu démarrer.`r`n`r`n$($_.Exception.Message)`r`n`r`nAucune action n'a été lancée par le démarrage. Consulter "+$logHint+". Ne pas contourner une restriction imposée par votre organisation."
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [Windows.MessageBox]::Show($message,'Pesto - démarrage impossible','OK','Error') | Out-Null
    } catch { Write-Host $message }
    exit 1
}
 finally {
    if($sessionMutex){try{if($sessionOwned){$sessionMutex.ReleaseMutex()}}finally{$sessionMutex.Dispose()}}
}

#requires -Version 5.1
# Définitions chargées dans la portée du moteur ; le writer démarre avec Initialize-AuditLog.


function Protect-PestoLogText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    # Défense supplémentaire ; aucun secret ne doit être journalisé à la source.
    # Les clés JSON et valeurs échappées/ tronquées doivent aussi être masquées.
    # Un contenu disproportionné ou un timeout ne restitue jamais le texte brut.
    if($Text.Length -gt 65536){return '[contenu masqué : taille excessive]'}
    $options=[Text.RegularExpressions.RegexOptions]::IgnoreCase
    $timeout=[TimeSpan]::FromMilliseconds(250)
    try{
        $safe=[regex]::Replace($Text,'(https?://)[^/\s@]+@','$1********@',$options,$timeout)
        # Les variantes préfixées/suffixées (sa_password, accessToken, secret_key)
        # sont sensibles aussi. Une valeur non quotée masque le reste de la ligne ;
        # un objet/tableau masque le reste du texte, sans deviner sa structure.
        $key='(?<![\w])["'']?[\w.-]*(?:authorization|password|motdepasse|passwd|pwd|token|secret|api[_-]?key|connectionstring)[\w.-]*["'']?\s*[:=]\s*'
        $pattern='('+$key+')(?:"(?:\\.|[^"\\])*(?:"|$)|''(?:\\.|[^''\\])*(?:''|$)|[\{\[][\s\S]*|[^\r\n]+)'
        return [regex]::Replace($safe,$pattern,'$1********',$options,$timeout)
    }catch{return '[contenu masqué : filtrage indisponible]'}
}

function New-PestoStructuredEvent {
    param([string]$Message,[string]$Level='INFO',[string]$Context='',
        [string]$OperationId='',[string]$WorkerId='',[string]$Stage='',[string]$BuildSHA256='',[AllowNull()]$Utc=$null)
    foreach($id in @($OperationId,$WorkerId)){if($id){$parsed=[Guid]::Empty;if(-not [Guid]::TryParse($id,[ref]$parsed)){throw 'Identifiant de journal invalide.'}}}
    if($BuildSHA256 -and $BuildSHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Empreinte de journal invalide.'}
    if($Level -notin @('DEBUG','INFO','WARN','ERROR','FATAL')){$Level='INFO'}
    $safe=Protect-PestoLogText $Message;if($safe.Length -gt 4000){$safe=$safe.Substring(0,4000)+' [tronqué]'}
    if($Context.Length -gt 80){$Context=$Context.Substring(0,80)};if($Stage.Length -gt 160){$Stage=$Stage.Substring(0,160)}
    # T018 : l'horodatage d'émission peut être conservé (flux direct) ; sinon l'horloge courante, comme avant.
    $stamp=$null
    if($null -ne $Utc){try{$stamp=([DateTime]$Utc).ToUniversalTime().ToString('o')}catch{$stamp=$null}}
    if(-not $stamp){$stamp=[DateTime]::UtcNow.ToString('o')}
    [pscustomobject]@{Schema=1;Utc=$stamp;OperationId=$OperationId;WorkerId=$WorkerId;
        BuildSHA256=$BuildSHA256;Stage=(Protect-PestoLogText $Stage);Context=(Protect-PestoLogText $Context);Level=$Level;Message=$safe}
}

function Write-PestoStructuredEvent {
    param([Parameter(Mandatory=$true)]$Event)
    # Même writer borné et même signalement des pertes que le journal existant.
    # Un préfixe stable distingue ces lignes JSON des messages lisibles existants.
    if(-not $script:AuditFile -or -not $script:PestoAuditWriter){return $false}
    $line='PESTO_EVENT '+($Event|ConvertTo-Json -Depth 4 -Compress)+[Environment]::NewLine
    return [bool](Write-PestoAuditQueued -Text $line)
}

function Get-PestoRemoteTaskLogTail {
    param([string]$ComputerName, [string]$LocalLogPath)
    try {
        if ([string]::IsNullOrWhiteSpace($LocalLogPath) -or $LocalLogPath.Length -lt 3) { return '' }
        $drive = $LocalLogPath.Substring(0, 1)
        $rest  = $LocalLogPath.Substring(2).TrimStart('\')
        $unc   = "\\$ComputerName\$drive`$\$rest"
        if (Test-Path -LiteralPath $unc) {
            return ((Get-Content -LiteralPath $unc -Tail 4 -ErrorAction Stop) -join ' | ')
        }
    } catch {}
    return ''
}

function Initialize-AuditLog {
    <# Choisit le premier dossier inscriptible et y ouvre le fichier du jour.
       L'interface peut démarrer sans journal, mais les mutations réelles seront
       ensuite bloquées par sécurité tant qu'aucun audit n'est inscriptible. #>
    param([string]$PreferredDir,$Now=$null)
    $script:AuditInitError=$null
    # Nouveau journal de session : l'état de perte repart de zéro. La bascule de jour le reporte explicitement.
    $script:PestoAuditLost=$false
    # Même horloge que la comparaison de bascule dans Write-PestoAuditQueued.
    $stamp=if($null -ne $Now){[DateTime]$Now}elseif($script:PestoAuditClock){[DateTime](& $script:PestoAuditClock)}else{Get-Date}
    $candidates = @()
    if ($PreferredDir) { $candidates += $PreferredDir }
    
    $localAppData = $env:LOCALAPPDATA
    if (-not $localAppData) {
        try { $localAppData = [Environment]::GetFolderPath('LocalApplicationData') } catch {}
    }
    if ($localAppData) {
        $candidates += (Join-Path $localAppData 'Pesto\logs')
    }

    $tempDir = $env:TEMP
    if (-not $tempDir) {
        try { $tempDir = [IO.Path]::GetTempPath() } catch {}
    }
    if ($tempDir) {
        $candidates += (Join-Path $tempDir 'Pesto\logs')
    }

    foreach ($dir in $candidates) {
        try {
            Assert-PestoPlainPath $dir
            if (-not (Test-Path -LiteralPath $dir)) { [void][IO.Directory]::CreateDirectory($dir) }
            $file = Join-Path $dir ("Pesto_{0}.log" -f $stamp.ToString('yyyy-MM-dd'))
            # Avant tout octet : un lien ou une jonction sur ce fichier ou un ancêtre est refusé.
            # AppendAllText suit un reparse point ; le writer C# revérifie ensuite le fichier ouvert.
            Assert-PestoPlainPath $file
            [System.IO.File]::AppendAllText($file, '', [System.Text.Encoding]::UTF8)  # test d'écriture réel
            $script:AuditFile = $file
            Initialize-PestoRuntimeTypes -Root $PSScriptRoot
            if($script:PestoAuditWriter){[void]$script:PestoAuditWriter.Close(2000)}
            $script:PestoAuditWriter=[Pesto.Runtime.AsyncAuditWriter]::new($file,2048)
            # Le nettoyage attend la configuration validée ; ne pas purger avec une valeur par défaut avant sa lecture.
            return
        } catch { $script:AuditInitError=$_.Exception.Message; continue }
    }
    if($script:AuditInitError){Write-Warning ('Journal d''audit indisponible : '+$script:AuditInitError+' Les mutations resteront bloquées.')}
}

function Test-PestoAuditWritable {
    # Barrière explicite avant mutation, distincte du journal UI asynchrone.
    if(-not $script:AuditFile -or -not $script:PestoAuditWriter){return $false}
    # Une perte constatée avant une bascule de jour reste bloquante pour toute la session.
    if($script:PestoAuditLost){return $false}
    if($script:PestoAuditWriter.Error -or $script:PestoAuditWriter.Dropped -gt 0 -or -not $script:PestoAuditWriter.Flush(1500)){return $false}
    $stream=$null
    try {
        Assert-PestoPlainPath $script:AuditFile
        $line='{0} [AUDIT] contrôle écriture avant mutation{1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),[Environment]::NewLine
        $bytes=[Text.Encoding]::UTF8.GetBytes($line)
        $stream=[IO.FileStream]::new($script:AuditFile,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
        return $true
    }catch{$script:PestoAuditError=Protect-PestoLogText $_.Exception.Message;return $false}
    finally{if($stream){$stream.Dispose()}}
}

function Write-AuditLine {
    <# Ajoute une ligne horodatée au journal persistant (silencieux si indisponible). #>
    param([string]$Text,[string]$Kind='info')
    $Text=Protect-PestoLogText $Text
    if (-not $script:AuditFile) { return }
    try {
        $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
                   $Kind.ToUpper().PadRight(4), $Text, [Environment]::NewLine
        [void](Write-PestoAuditQueued -Text $line)
    } catch { }
}

function Write-Log {
    <# Cœur du log de diagnostic persistant : ligne horodatée + bloc détail si erreur.
       Silencieux si aucun fichier inscriptible. -Level DEBUG|INFO|WARN|ERROR|FATAL ;
       -Err = ErrorRecord/Exception à détailler ; -Context = sous-système (ex. 'AD', 'run-queue'). #>
    param(
        [string]$Message,
        [ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level = 'INFO',
        $Err,
        [string]$Context
    )
    if (-not $script:AuditFile) { return }
    $rank = $script:LevelRank; if (-not $rank) { $rank = @{ DEBUG=0; INFO=1; WARN=2; ERROR=3; FATAL=4 } }
    $min  = if ($script:LogLevel -and $rank.ContainsKey($script:LogLevel)) { $rank[$script:LogLevel] } else { 1 }
    if (-not $Err -and $rank[$Level] -lt $min) { return }   # une erreur est TOUJOURS journalisée
    try {
        $ctx = if ($Context) { "[$Context] " } else { '' }
        $sb  = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine(('{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.PadRight(5), $ctx, $Message))
        if ($Err) { $d = Get-ErrorDetail $Err; if ($d) { [void]$sb.AppendLine($d) } }
        [void](Write-PestoAuditQueued -Text (Protect-PestoLogText $sb.ToString()))
    } catch { }
}

function Open-AuditLog {
    <# Ouvre le journal d'audit du jour dans l'Explorateur (fichier sélectionné). #>
    if (-not $script:AuditFile) { Show-MsgInfo "Le journal d'audit n'est pas disponible (aucun dossier inscriptible)." 'Journal'; return }
    try {
        if (Test-Path $script:AuditFile) { Start-Process explorer.exe "/select,`"$script:AuditFile`"" }
        else { Start-Process explorer.exe (Split-Path $script:AuditFile -Parent) }
    } catch { Show-MsgError "Impossible d'ouvrir le journal :`n$($_.Exception.Message)" }
}

function Get-LogBrush {
    param([string]$Kind)
    $t = $script:Themes[$script:CurrentTheme]
    switch ($Kind) {
        'head' { New-Brush $t['HeadFg'] }
        'ok'   { New-Brush $t['OkFg'] }
        'err'  { New-Brush $t['ErrFg'] }
        'warn' { New-Brush $t['WarnFg'] }
        default{ New-Brush $t['FgText'] }
    }
}

function New-LogParagraph {
    param($Entry)
    $p = New-Object Windows.Documents.Paragraph
    $p.Margin = '0,0,0,2'
    $run = New-Object Windows.Documents.Run ("{0}  {1}" -f $Entry.Time, $Entry.Text)
    $run.Foreground = Get-LogBrush $Entry.Kind
    if ($Entry.Kind -eq 'head') { $run.FontWeight = 'Bold' }
    [void]$p.Inlines.Add($run)
    return $p
}

function Add-LogLine {
    param([string]$Text,[string]$Kind='info')
    $Text=Protect-PestoLogText $Text
    $script:LogSequence=[long]$script:LogSequence+1
    $entry=[pscustomobject]@{Sequence=$script:LogSequence;Time=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Text=$Text;Kind=$Kind}
    if($null -ne $script:LogEntries){
        [void]$script:LogEntries.Add($entry)
        while($script:LogEntries.Count -gt 1500){$script:LogEntries.RemoveAt(0)}
    }
    # La trace disque n'attend pas le rendu du journal. Le timer regroupe les mises à jour UI.
    Write-AuditLine $Text $Kind
    $script:PestoLogDirty=$true
}

function Add-LogSeparator {
    if ($null -ne $script:LogEntries -and $script:LogEntries.Count -gt 0 -and $LogBox) {
        [void]$LogBox.Document.Blocks.Add((New-Object Windows.Documents.Paragraph))
    }
    if ($script:AuditFile) {
        [void](Write-PestoAuditQueued -Text ([Environment]::NewLine))
    }
}

function Get-PestoFilteredLogEntries {
    param([object[]]$Entries=@(),[string]$Query='',[ValidateSet('','All','Info','Warn','Error')][string]$Level='All')
    foreach($entry in $Entries){
        if($Query -and ([string]$entry.Text).IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        $kind=([string]$entry.Kind).ToLowerInvariant()
        if($Level -eq 'Error' -and $kind -ne 'err'){continue}
        if($Level -eq 'Warn' -and $kind -ne 'warn'){continue}
        if($Level -eq 'Info' -and $kind -in @('err','warn')){continue}
        $entry
    }
}
function Invoke-PestoLogLevel {
    param($Sender,$EventArgs)
    $script:LogLevel=if($Sender.SelectedItem){[string]$Sender.SelectedItem.Tag}else{'All'}
    $script:LogForceRefresh=$true;Render-Log
}
function Copy-PestoLogErrors {
    $entries=@(Get-PestoFilteredLogEntries -Entries @($script:LogEntries) -Level Error)
    if(-not $entries.Count){Show-MsgInfo 'Aucune erreur dans les 1 500 derniers événements conservés.' 'Journal';return}
    $text=(@($entries|ForEach-Object{[string]$_.Time+'  '+(Protect-PestoLogText ([string]$_.Text))}) -join [Environment]::NewLine)
    try{[Windows.Clipboard]::SetText($text)}catch{Show-MsgError $_.Exception.Message 'Copie du journal'}
}

function Render-Log {
    if(-not $LogBox){return}
    if(-not $script:LogFollow -and -not $script:LogForceRefresh){$script:PestoLogDirty=$false;return}
    $top=$LogBox.VerticalOffset
    $items=@(Get-PestoFilteredLogEntries -Entries @($script:LogEntries) -Query ([string]$script:LogFilter) -Level ([string]$script:LogLevel))
    $visible=@($items|Select-Object -Last 500)
    $size=if($script:LogFontSize){[Math]::Max(10,[Math]::Min(22,[double]$script:LogFontSize))}else{12}
    $key=[string]$script:LogFilter+'|'+[string]$script:LogLevel+'|'+$script:CurrentTheme+'|'+$size+'|'+$script:LogWrap
    $rebuild=$script:LogForceRefresh -or $script:LogRenderKey -ne $key -or -not $script:LastRenderedSequence
    if($rebuild){$LogBox.Document.Blocks.Clear();$script:LastRenderedSequence=0}
    $LogBox.FontSize=$size;$LogBox.Document.FontSize=$size
    $LogBox.Document.PageWidth=if($script:LogWrap){[double]::NaN}else{10000.0}
    foreach($entry in $visible){
        if($entry.Sequence -le $script:LastRenderedSequence){continue}
        $paragraph=New-LogParagraph $entry;$paragraph.FontSize=$size
        [void]$LogBox.Document.Blocks.Add($paragraph);$script:LastRenderedSequence=[long]$entry.Sequence
    }
    while($LogBox.Document.Blocks.Count -gt 500){$LogBox.Document.Blocks.Remove($LogBox.Document.Blocks.FirstBlock)}
    if($script:LogFollow){$LogBox.ScrollToEnd()}else{$LogBox.ScrollToVerticalOffset($top)}
    if($script:SuiteUI -and $script:SuiteUI.SuiteLogCount){$script:SuiteUI.SuiteLogCount.Text=('{0} affichés / {1} correspondants / {2} en mémoire' -f $visible.Count,$items.Count,$script:LogEntries.Count)}
    $script:LogRenderKey=$key;$script:PestoLogDirty=$false;$script:LogForceRefresh=$false
}

function Clear-Log { $script:LastRenderedSequence=0;$script:LogForceRefresh=$true;$script:LogEntries.Clear(); if ($LogBox) { $LogBox.Document.Blocks.Clear() } }


function Write-PestoAuditQueued {
    param([string]$Text)
    if(-not $script:PestoAuditWriter){$script:PestoAuditError='Journal non initialisé.';return $false}
    
    # Vérification de la bascule de jour (Date locale)
    $now = if ($script:PestoAuditClock) { & $script:PestoAuditClock } else { Get-Date }
    $currentDateStr = $now.ToString('yyyy-MM-dd')
    $fileName = Split-Path $script:AuditFile -Leaf
    $fileDateStr = $fileName -replace '^Pesto_' -replace '\.log$'

    if ($currentDateStr -ne $fileDateStr) {
        # Une ligne perdue dans l'ancien fichier ne doit pas être effacée par le writer neuf :
        # l'état de perte est capturé avant la fermeture et reste bloquant pour la session.
        $old=$script:PestoAuditWriter
        $lost=[bool]$script:PestoAuditLost -or [bool]$old.Error -or $old.Dropped -gt 0
        try {
            # 1. Écrire la ligne de transition dans l'ancien fichier
            $transitionMsg = "Suite dans Pesto_$currentDateStr.log"
            if(-not $old.TryWrite(('{0} [AUDIT] {1}{2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $transitionMsg, [Environment]::NewLine))){$lost=$true}

            # 2. Fermer l'ancien writer ; faux = erreur, perte ou vidage inachevé.
            if(-not $old.Close(2000)){$lost=$true}

            # 3. Réinitialiser le journal avec le nouveau nom dans le même dossier, même horloge
            $dir = Split-Path $script:AuditFile -Parent
            Initialize-AuditLog -PreferredDir $dir -Now $now
            if($lost){
                $script:PestoAuditLost=$true
                $script:PestoAuditError='Journal incomplet avant bascule de jour. Mutations bloquées pour cette session.'
                Set-PestoPersistenceWarning $script:PestoAuditError
            }

            # 4. Écrire la ligne de reprise dans le nouveau fichier
            $resumeMsg = "Suite du journal du $currentDateStr"
            [void]$script:PestoAuditWriter.TryWrite(('{0} [AUDIT] {1}{2}' -f $now.ToString('yyyy-MM-dd HH:mm:ss'), $resumeMsg, [Environment]::NewLine))
        } catch {
            $script:PestoAuditLost=$true
            $script:PestoAuditError = 'Erreur bascule journal : ' + $_.Exception.Message + ' Mutations bloquées pour cette session.'
            Set-PestoPersistenceWarning $script:PestoAuditError
        }
    }

    $ok=$script:PestoAuditWriter.TryWrite($Text)
    if(-not $ok){$script:PestoAuditError='Journal incomplet : tampon plein ou erreur disque. Prochaine mutation bloquée.';Set-PestoPersistenceWarning $script:PestoAuditError}
    return $ok
}

function Get-PestoAuditHealth {
    $writer=$script:PestoAuditWriter
    return [pscustomobject]@{Ready=([bool]$writer -and -not $writer.Error -and $writer.Dropped -eq 0 -and -not $script:PestoAuditLost);
        Pending=$(if($writer){$writer.Pending}else{0});Written=$(if($writer){$writer.Written}else{0});
        Dropped=$(if($writer){$writer.Dropped}else{0});Error=$(if($writer -and $writer.Error){Protect-PestoLogText $writer.Error}else{[string]$script:PestoAuditError})}
}

function Stop-PestoAuditWriter {
    if($script:PestoAuditWriter){
        $ok=$script:PestoAuditWriter.Close(3000)
        if(-not $ok){$script:PestoAuditError='Le journal de confort n''a pas pu être entièrement vidé. Les reçus restent indépendants.'}
        $script:PestoAuditWriter=$null
    }
}

function Set-PestoPersistenceWarning {
    param([string]$Message)
    $script:PestoPersistenceWarning=Protect-PestoLogText $Message
    if($Win){$warning=$Win.FindName('PestoPersistenceWarning');if($warning){$warning.Text='! '+$script:PestoPersistenceWarning;$warning.Visibility='Visible'}}
}
function Remove-PestoExpiredLogs {
    param([string]$Directory,[ValidateRange(0,3650)][int]$Days=30,[string]$CurrentFile='', [DateTime]$Now=[DateTime]::UtcNow)
    if($Days -eq 0){return 0}
    Assert-PestoPlainPath $Directory;$count=0
    foreach($file in @(Get-ChildItem -LiteralPath $Directory -Filter 'Pesto_*.log' -File -ErrorAction Stop)){
        if($file.Name -notmatch '^Pesto_\d{4}-\d{2}-\d{2}\.log$' -or $file.FullName -ieq $CurrentFile -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
        if($file.LastWriteTimeUtc -lt $Now.AddDays(-$Days)){Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop;$count++}
    }
    return $count
}

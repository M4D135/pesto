#requires -Version 5.1
# Cache d'affichage uniquement. Les mutations relisent Get-PestoInterventions sans ce cache.
function New-PestoInterventionCatalogCache {
    [hashtable]::Synchronized(@{Root='';Files=@{};Version=0L;Clock=[Diagnostics.Stopwatch]::StartNew();Coordinator=(New-PestoReadCoordinator)})
}
function Clear-PestoInterventionCatalogCache {
    param([Parameter(Mandatory=$true)][hashtable]$Cache)
    [Threading.Monitor]::Enter($Cache.SyncRoot)
    try{$Cache.Files=@{};$Cache.Root='';$Cache.Version=[long]$Cache.Version+1}
    finally{[Threading.Monitor]::Exit($Cache.SyncRoot)}
}
function Copy-PestoCatalogValue {
    param($Value)
    if($null -eq $Value){return $null}
    if($Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Array]){return ,@(foreach($item in $Value){Copy-PestoCatalogValue $item})}
    $copy=[ordered]@{};foreach($property in $Value.PSObject.Properties){$copy[$property.Name]=Copy-PestoCatalogValue $property.Value}
    return [pscustomobject]$copy
}
function Read-PestoInterventionCatalogCachedCore {
    param([string]$Root=(Get-PestoInterventionRoot),[Parameter(Mandatory=$true)][hashtable]$Cache,
        [switch]$Force,[ValidateRange(0,30)][int]$MaximumAgeSeconds=5)
    if($Cache.Clock -isnot [Diagnostics.Stopwatch] -or $Cache.Files -isnot [hashtable]){throw 'Cache créé par New-PestoInterventionCatalogCache requis.'}
    Assert-PestoPlainPath $Root
    $full=[IO.Path]::GetFullPath($Root)
    [Threading.Monitor]::Enter($Cache.SyncRoot)
    try{
        if($Cache.Root -cne $full){$Cache.Files=@{};$Cache.Root=$full;$Cache.Version=[long]$Cache.Version+1}
        try{$directory=Get-Item -LiteralPath $full -Force -ErrorAction Stop}
        catch [Management.Automation.ItemNotFoundException]{
            if($Cache.Files.Count){$Cache.Files=@{};$Cache.Version=[long]$Cache.Version+1}
            return [pscustomobject]@{Entries=@();ValidCount=0;InvalidCount=0;Truncated=$false;ScannedCount=0;Version=$Cache.Version;CacheHits=0;ParsedFiles=0}
        }
        if(-not $directory.PSIsContainer){throw 'Le registre des interventions n''est pas un dossier.'}
        $files=@(Get-ChildItem -LiteralPath $full -Filter '*.json' -File -Force -ErrorAction Stop|Select-Object -First 5001)
        $seen=@{};$entries=[Collections.Generic.List[object]]::new();$valid=0;$invalid=0;$hits=0;$parsed=0;$changed=$false
        foreach($file in $files|Select-Object -First 5000){
            $key=$file.Name;$seen[$key]=$true;$stamp=([string]$file.Length)+'|'+[string]$file.LastWriteTimeUtc.Ticks
            $old=$Cache.Files[$key];$now=[long]$Cache.Clock.ElapsedMilliseconds
            if(-not $Force -and $old -and $old.Stamp -ceq $stamp -and $now-$old.ReadAt -lt $MaximumAgeSeconds*1000){$entry=$old.Entry;$hits++}
            else{
                $parsed++
                try{
                    $receipt=Read-PestoIntervention -Path $file.FullName
                    $entry=[pscustomobject]@{Id=$receipt.OperationId;Readable=$true;Receipt=$receipt;FileName=$file.Name;Issue=''}
                }catch{$entry=[pscustomobject]@{Id='invalid:'+$file.Name;Readable=$false;Receipt=$null;FileName=$file.Name;Issue='Reçu illisible ou invalide. Faites contrôler ce fichier par le support. Aucun verrou levé.'}}
                $Cache.Files[$key]=@{Stamp=$stamp;ReadAt=$now;Entry=$entry};$changed=$true
            }
            if($entry.Readable){$valid++}else{$invalid++}
            # Ne pas remettre au consommateur les objets mutables détenus par le cache.
            $entries.Add((Copy-PestoCatalogValue $entry))
        }
        foreach($key in @($Cache.Files.Keys)){if(-not $seen.ContainsKey($key)){$Cache.Files.Remove($key);$changed=$true}}
        if($changed){$Cache.Version=[long]$Cache.Version+1}
        [pscustomobject]@{Entries=$entries.ToArray();ValidCount=$valid;InvalidCount=$invalid;Truncated=($files.Count -gt 5000);ScannedCount=$files.Count;Version=$Cache.Version;CacheHits=$hits;ParsedFiles=$parsed}
    }finally{[Threading.Monitor]::Exit($Cache.SyncRoot)}
}

function Get-PestoInterventionCatalogCached {
    param([string]$Root=(Get-PestoInterventionRoot),[Parameter(Mandatory=$true)][hashtable]$Cache,
        [switch]$Force,[ValidateRange(0,30)][int]$MaximumAgeSeconds=5)
    if($Cache.Coordinator -isnot [hashtable]){throw 'Cache créé par New-PestoInterventionCatalogCache requis.'}
    $full=[IO.Path]::GetFullPath($Root)
    $key=$full+'|'+[string][bool]$Force+'|'+[string]$MaximumAgeSeconds
    $read=Invoke-PestoReadCoalesced -Coordinator $Cache.Coordinator -Key $key -ReadAction {
        param($Path,$State,$Refresh,$Age)
        Read-PestoInterventionCatalogCachedCore -Root $Path -Cache $State -Force:$Refresh -MaximumAgeSeconds $Age
    } -ArgumentList @($full,$Cache,[bool]$Force,$MaximumAgeSeconds)
    # Chaque consommateur peut créer sa projection sans modifier celle d''un autre lecteur.
    return (Copy-PestoCatalogValue $read.Value)
}

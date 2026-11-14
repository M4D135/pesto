#requires -Version 5.1
# Hôte des deux entrées CLI. Une seule définition : les bancs refusent un nom de fonction répété.
function ConvertTo-PestoCliJson {
    param($Value,[int]$Depth)
    # ASCII reste de l'UTF-8 valide et ne change pas sous une console OEM ou ANSI.
    # Chaque unité UTF-16 hors ASCII, y compris chaque moitié d'une paire surrogate,
    # devient un échappement JSON \uXXXX. ConvertFrom-Json réassemble la paire.
    # L'encodage de la console appelante n'est pas modifié.
    $json=$Value|ConvertTo-Json -Depth $Depth -Compress
    return [regex]::Replace($json,'[^\x00-\x7F]',[Text.RegularExpressions.MatchEvaluator]{param($m) '\u{0:x4}' -f [int][char]$m.Value[0]})
}
function Get-PestoModuleAnalysisCachePath {
    $cache = $env:PSModuleAnalysisCachePath
    if (-not $cache) {
        $localAppData = $env:LOCALAPPDATA
        if (-not $localAppData) {
            try { $localAppData = [Environment]::GetFolderPath('LocalApplicationData') } catch {}
        }
        if ($localAppData) {
            $cache = Join-Path $localAppData 'Microsoft\Windows\PowerShell\ModuleAnalysisCache'
        }
    }
    return $cache
}

function Initialize-PestoCliProcess {
    # Windows PowerShell 5.1 écrit « Preparing modules for first use. » sur l'hôte,
    # sans tenir compte de $ProgressPreference. Si stderr est redirigé, cet enregistrement
    # devient du CLIXML et une task sequence rejette un JSON pourtant valide.
    # Le cache d'analyse des modules est commun au processus : on le prépare dans un
    # runspace imbriqué, dont l'hôte par défaut n'écrit pas le stderr de ce processus,
    # et seulement quand le fichier de cache est encore absent.
    try {
        $global:ProgressPreference='SilentlyContinue'
        if($PSVersionTable.PSEdition -eq 'Core'){return}
        $cache = Get-PestoModuleAnalysisCachePath
        if(-not $cache){return}
        if(Test-Path -LiteralPath $cache){return}
        $nested=$null
        try{
            $nested=[powershell]::Create()
            [void]$nested.AddScript('Set-StrictMode -Off; $global:ProgressPreference=''SilentlyContinue''; $null=Get-Module -ListAvailable -ErrorAction SilentlyContinue').Invoke()
        }catch{}
        finally{if($null -ne $nested){$nested.Dispose()}}
    } catch {}
}

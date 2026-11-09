param([Parameter(Mandatory=$true)][string]$Root)
# Vrai parseur PowerShell de la session : aucune exécution du code analysé.
$total=0;$bad=0
$files=Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.ps1 | Where-Object { $_.Extension -eq '.ps1' } | Sort-Object FullName
foreach($f in $files){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
    $total++
    foreach($e in @($errors)){
        $bad++
        '{0}:{1}:{2} {3} | {4}' -f $f.FullName.Substring($Root.Length).TrimStart('/','\'),$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.ErrorId,$e.Message
    }
}
"FICHIERS=$total ERREURS=$bad PARSEUR=PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
if($bad){exit 1}

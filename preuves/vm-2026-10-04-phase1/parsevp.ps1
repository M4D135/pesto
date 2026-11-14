# Passe parseur de validate_pesto.py (texte PARSE copié tel quel), sous Windows PowerShell 5.1.
$env:PESTO_PARSE_ROOT = 'C:\PestoTest'
$json = & {
$ErrorActionPreference='Stop';$out=foreach($f in (Get-ChildItem -LiteralPath $env:PESTO_PARSE_ROOT -Recurse -File -Filter *.ps1 | Where-Object { $_.Extension -eq '.ps1' })){$t=$null;$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e);[pscustomobject]@{Path=$f.FullName;Errors=@($e|ForEach-Object{'{0}:{1} {2}' -f $_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message})}};[pscustomobject]@{Engine=[string]$PSVersionTable.PSVersion;Edition=[string]$PSVersionTable.PSEdition;Files=@($out)}|ConvertTo-Json -Depth 4 -Compress
}
$d = $json | ConvertFrom-Json
$f = @($d.Files)
'moteur : ' + $d.Engine + ' ' + $d.Edition
'fichiers : ' + $f.Count + ' ; avec erreurs : ' + @($f | Where-Object { @($_.Errors).Count -gt 0 }).Count
'hors .ps1 : ' + @($f | Where-Object { [IO.Path]::GetExtension($_.Path) -ne '.ps1' }).Count
'controles attendus avec --require-parser : 340 + 1 + ' + $f.Count + ' = ' + (341 + $f.Count)

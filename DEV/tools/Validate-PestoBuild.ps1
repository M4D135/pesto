#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference='Stop'
# No application startup, directory query or mutation. Parse runtime sources,
# then load only the closed configuration validation function definitions.
$needed=@('Assert-PestoClosedObject','Test-PestoPropertyPresent','Convert-Value-TF',
  'Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','ConvertTo-PestoPolicy','Test-CfgValid',
  'Get-PestoDefaultNamingConvention','Assert-PestoNamingConvention','Get-PestoNamingResolutionNonce','ConvertTo-PestoScenario','Get-PestoFacetPattern','Get-PestoActiveNamingConvention','Get-PestoNamingLayout','Merge-PestoManagedPolicy','Get-PestoManagedPolicy')
$definitions=@{}
foreach($file in @('Pesto-Core.ps1','Pesto-Configuration.ps1','Pesto-Policy.ps1','Pesto-Operations.ps1','Pesto-Directory.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1','Pesto-ManagedPolicy.ps1')){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Root ('wad/'+$file)),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Source invalide : '+$file)}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $needed){$definitions[$node.Name]=$node.Body.GetScriptBlock()}
    }
}
foreach($name in $needed){
    if(-not $definitions.ContainsKey($name)){throw ('Validation manquante : '+$name)}
    Set-Item -Path ('Function:'+ $name) -Value $definitions[$name]
}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $Root 'wad') -Filter '*.ps1' -File){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw (($errors|ForEach-Object{$_.ToString()}) -join "`n")}
}
$file=Join-Path $Root 'wad/cfg.json'
if((Get-Item -LiteralPath $file).Length -gt 1MB){throw 'Configuration trop volumineuse (1 Mio maximum).'}
$text=[IO.File]::ReadAllText($file,[Text.UTF8Encoding]::new($false,$true))
$config=$text|ConvertFrom-Json -ErrorAction Stop
$template=Join-Path $Root 'tools/cfg.template.json'
$isNeutral=(Test-Path -LiteralPath $template) -and ((Get-FileHash -LiteralPath $file).Hash -ceq (Get-FileHash -LiteralPath $template).Hash)
$errors=if($isNeutral){@()}else{@(Test-CfgValid $config)}
if($errors.Count){throw ('Configuration refusée : '+($errors -join '; '))}
Write-Output 'Syntaxe et configuration : PASS (sans accès AD ni lancement de Pesto).'

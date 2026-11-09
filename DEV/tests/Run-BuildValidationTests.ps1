#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Tool=Join-Path $Root 'tools/Validate-PestoBuild.ps1'
if(-not (Test-Path -LiteralPath $Tool)){throw 'Outil de validation absent.'}

function Invoke-Validation {
    param([string]$TempRoot)
    try {
        $out=& $Tool -Root $TempRoot
        return @{Exit=0;Output=($out -join "`n")}
    } catch {return @{Exit=1;Output=$_.Exception.Message}}
}

$script:ValidationTempRoots=[Collections.Generic.List[string]]::new()
function New-TestEnv {
    param([string]$Name,[object]$Config,[bool]$Neutral=$false)
    $Temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoVal_'+$Name+'_'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Temp -Force | Out-Null
    $script:ValidationTempRoots.Add($Temp)
    $Wad=Join-Path $Temp 'wad'
    New-Item -ItemType Directory -Path $Wad -Force | Out-Null
    # Copie des sources necessaires
    foreach($f in @('Pesto-Core.ps1','Pesto-Configuration.ps1','Pesto-Policy.ps1','Pesto-Operations.ps1','Pesto-Directory.ps1','Pesto-Contracts.ps1','Pesto-Safety.ps1','Pesto-ManagedPolicy.ps1')){
        $src=Join-Path $Root ('wad/'+$f)
        if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination (Join-Path $Wad $f) -Force}
    }
    # Template neutre
    $Tools=Join-Path $Temp 'tools'
    New-Item -ItemType Directory -Path $Tools -Force | Out-Null
    $TplSrc=Join-Path $Root 'tools/cfg.template.json'
    if(Test-Path -LiteralPath $TplSrc){Copy-Item -LiteralPath $TplSrc -Destination (Join-Path $Tools 'cfg.template.json') -Force}
    # Config
    $CfgPath=Join-Path $Wad 'cfg.json'
    if($Neutral){
        if(Test-Path -LiteralPath $TplSrc){Copy-Item -LiteralPath $TplSrc -Destination $CfgPath -Force}
        else{throw 'Template neutre manquant pour test.'}
    }else{
        $Config|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $CfgPath -Encoding UTF8
    }
    return $Temp
}

try {
$Tests=@()

# 1. Exemple (valide)
$ExSrc=Join-Path $Root 'wad/cfg.example.json'
if(-not(Test-Path -LiteralPath $ExSrc)){throw 'Configuration exemple requise.'}
if(Test-Path -LiteralPath $ExSrc){
    $Cfg=Get-Content -LiteralPath $ExSrc -Raw|ConvertFrom-Json
    $T=New-TestEnv -Name 'Example' -Config $Cfg
    $R=Invoke-Validation -TempRoot $T
    $Tests+=[pscustomobject]@{Name='Exemple valide';Pass=($R.Exit -eq 0);Msg=$R.Output}
    Remove-Item -LiteralPath $T -Recurse -Force
}

# 2. Nommage custom valide
$CustomCfg=Get-Content -LiteralPath $ExSrc -Raw|ConvertFrom-Json
$CustomCfg|Add-Member -NotePropertyName 'NamingConvention' -NotePropertyValue ([pscustomobject]@{
    Schema=1;Id='custom';Tokens=@('Service','Number','Type','Prefix','Site');
    Widths=@{Prefix=3;Site=2;Service=2;Number=2};Types='PSV'
}) -Force
$CustomCfg.CONF[0].Prefixe='123';$CustomCfg.CONF[0].PreprodSite='IT'
$T=New-TestEnv -Name 'CustomNaming' -Config $CustomCfg
$R=Invoke-Validation -TempRoot $T
$Tests+=[pscustomobject]@{Name='Nommage custom valide';Pass=($R.Exit -eq 0);Msg=$R.Output}
Remove-Item -LiteralPath $T -Recurse -Force

# 3. Scenario valide
$ScenarioCfg=Get-Content -LiteralPath $ExSrc -Raw|ConvertFrom-Json
$ScenarioCfg|Add-Member -NotePropertyName 'POLICY' -NotePropertyValue ([pscustomobject]@{
    Schema=1;Scenario=[pscustomobject]@{Schema=1;Name='Test';Required=@('Type');Allowed=@{};Locked=@{}}
}) -Force
$T=New-TestEnv -Name 'ScenarioValid' -Config $ScenarioCfg
$R=Invoke-Validation -TempRoot $T
$Tests+=[pscustomobject]@{Name='Scenario valide';Pass=($R.Exit -eq 0);Msg=$R.Output}
Remove-Item -LiteralPath $T -Recurse -Force

# 4. Convention invalide (largeur trop grande)
$BadConvCfg=Get-Content -LiteralPath $ExSrc -Raw|ConvertFrom-Json
$BadConvCfg|Add-Member -NotePropertyName 'NamingConvention' -NotePropertyValue ([pscustomobject]@{
    Schema=1;Id='bad';Tokens=@('Type','Prefix','Site','Service','Number');
    Widths=@{Prefix=20;Site=2;Service=3;Number=3};Types='PSV'
}) -Force
$T=New-TestEnv -Name 'BadConvention' -Config $BadConvCfg
$R=Invoke-Validation -TempRoot $T
$Tests+=[pscustomobject]@{Name='Convention invalide (refus)';Pass=($R.Exit -ne 0 -and $R.Output -match 'Configuration refusée');Msg=$R.Output}
Remove-Item -LiteralPath $T -Recurse -Force

# 5. Scenario malforme
$BadScenCfg=Get-Content -LiteralPath $ExSrc -Raw|ConvertFrom-Json
$BadScenCfg|Add-Member -NotePropertyName 'POLICY' -NotePropertyValue ([pscustomobject]@{
    Schema=1;Scenario=[pscustomobject]@{Schema=1;Name='Bad';Required=@('UnknownField');Allowed=@{};Locked=@{}}
}) -Force
$T=New-TestEnv -Name 'BadScenario' -Config $BadScenCfg
$R=Invoke-Validation -TempRoot $T
$Tests+=[pscustomobject]@{Name='Scenario malforme (refus)';Pass=($R.Exit -ne 0 -and $R.Output -match 'Configuration refusée');Msg=$R.Output}
Remove-Item -LiteralPath $T -Recurse -Force

# 6. Template neutre (doit passer sans erreur de chargement)
$T=New-TestEnv -Name 'Neutral' -Config $null -Neutral $true
$R=Invoke-Validation -TempRoot $T
$Tests+=[pscustomobject]@{Name='Template neutre';Pass=($R.Exit -eq 0);Msg=$R.Output}
Remove-Item -LiteralPath $T -Recurse -Force

$Failures=@($Tests|Where-Object{-not $_.Pass})
if($Failures.Count){
    foreach($f in $Failures){Write-Host ('ECHEC: '+$f.Name+' -> '+$f.Msg)}
    throw ('Validation échouée sur '+$Failures.Count+' cas.')
}
Write-Host ('Validation Build : '+$Tests.Count+' cas PASS.')
} finally {
    foreach($path in $script:ValidationTempRoots){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force}}
}

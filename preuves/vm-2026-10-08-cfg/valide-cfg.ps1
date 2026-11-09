# Validation du cfg.json commenté avec les vraies fonctions de Pesto (Windows PowerShell 5.1).
param([string]$Wad='C:\PestoTest\wad',[string]$NewPath='C:\PestoTest-run\cfg-commente.json',[string]$OldPath='C:\PestoTest-run\cfg-livre.json')
$ErrorActionPreference='Stop'
$R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){$R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''}))}
$want=@('Test-CfgValid','ConvertTo-PestoPolicy','Assert-PestoClosedObject','Test-PestoPropertyPresent','Test-PestoDnsName','Test-PestoOUPath','Split-PestoDistinguishedName','Get-PestoDomainFromDN','Convert-Value-TF','Get-PestoConfigurationSignature','ConvertTo-PestoCanonicalValue','Get-PestoStableHash','ConvertTo-PestoOrderedMap','Set-PestoMapValue')
$found=@{}
foreach($f in Get-ChildItem $Wad -Filter 'Pesto-*.ps1'){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e)
    foreach($fn in @($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst]},$false))){if($fn.Name -in $want -and -not $found.ContainsKey($fn.Name)){$found[$fn.Name]=$fn.Extent.Text}}
}
foreach($n in $want){if(-not $found.ContainsKey($n)){throw "Fonction absente : $n"};. ([scriptblock]::Create($found[$n]))}
try{
    $raw=Get-Content $NewPath -Raw -Encoding UTF8
    $cfgNew=$raw|ConvertFrom-Json
    $cfgOld=Get-Content $OldPath -Raw -Encoding UTF8|ConvertFrom-Json
    Check 'Lecture JSON par Windows PowerShell 5.1' ($null -ne $cfgNew)
    $errs=@(Test-CfgValid $cfgNew)
    Check 'Test-CfgValid : aucune erreur' ($errs.Count -eq 0) ($errs -join ' | ')
    Check 'Ancien fichier : aucune erreur non plus' (@(Test-CfgValid $cfgOld).Count -eq 0) (@(Test-CfgValid $cfgOld) -join ' | ')
    Check 'Simulation = false (mode réel)' (-not (Convert-Value-TF $cfgNew.DEBUG.Simulation -Strict)) ([string]$cfgNew.DEBUG.Simulation)
    Check 'GUI = false' (-not (Convert-Value-TF $cfgNew.DEBUG.GUI -Strict))
    $p0=ConvertTo-PestoPolicy $null;$p1=ConvertTo-PestoPolicy $cfgNew.POLICY
    Check 'POLICY explicite = valeurs par défaut' (($p0|ConvertTo-Json -Compress) -eq ($p1|ConvertTo-Json -Compress)) (($p0|ConvertTo-Json -Compress)+' / '+($p1|ConvertTo-Json -Compress))
    # Valeurs lues par le moteur (mêmes expressions que Pesto-Core.ps1) : identiques à l'ancien fichier, sauf Simulation.
    function Engine($cfg){$conf=@($cfg.CONF)[0];[pscustomobject]@{
        PRD=Convert-Value-TF $conf.DirectProd;GUI=Convert-Value-TF $cfg.Debug.GUI
        CLEAR=if($null -ne $conf.ClearProtectionOnMove){Convert-Value-TF $conf.ClearProtectionOnMove}else{$true}
        ROLLBACK=if($null -ne $conf.MoveRollbackOnRenameFail){Convert-Value-TF $conf.MoveRollbackOnRenameFail}else{$false}
        ENTRA=if([string]$conf.EntraPolicy -in @('HybridOnly','Disabled')){[string]$conf.EntraPolicy}else{'HybridOnly'}
        Domaine=$conf.Domaine;Prefixe=$conf.Prefixe;Pre=$conf.PreprodSite;Scan=$conf.OUScanNoms;Buffer=$conf.Buffer;Dark=$conf.DarkMode;ADM=$conf.ADM
        Tags=($cfg.TAGS|ConvertTo-Json -Compress);Base=($cfg.OUBase|ConvertTo-Json -Compress);Site=($cfg.OUSite|ConvertTo-Json -Compress)}}
    $e0=Engine $cfgOld|ConvertTo-Json -Compress;$e1=Engine $cfgNew|ConvertTo-Json -Compress
    Check 'Valeurs appliquées par le moteur identiques à l''ancien fichier (hors Simulation)' ($e0 -eq $e1) ($e0+' / '+$e1)
    Check 'Ancien fichier : Simulation était true' (Convert-Value-TF $cfgOld.DEBUG.Simulation -Strict)
    # « Enregistrer les paramètres » : même construction que Build-CfgFromUI, les commentaires restent.
    $conf=ConvertTo-PestoOrderedMap ((@($cfgNew.CONF))[0]);Set-PestoMapValue $conf 'Buffer' '10'
    $debug=ConvertTo-PestoOrderedMap $cfgNew.DEBUG;Set-PestoMapValue $debug 'Simulation' 'false'
    $cfg=ConvertTo-PestoOrderedMap $cfgNew;Set-PestoMapValue $cfg 'DEBUG' $debug;Set-PestoMapValue $cfg 'CONF' ([object[]]@($conf))
    $back=($cfg|ConvertTo-Json -Depth 20)|ConvertFrom-Json
    Check 'Après « Enregistrer » : commentaires conservés (racine, CONF, DEBUG, POLICY)' ($back._A_LIRE -and (@($back.CONF)[0])._Domaine -and $back.DEBUG._Simulation -and $back._POLICY.MaxBatch) ''
    Check 'Après « Enregistrer » : toujours valide' (@(Test-CfgValid $back).Count -eq 0) (@(Test-CfgValid $back) -join ' | ')
    Check 'Après « Enregistrer » sans changement : pas de redémarrage (signature identique)' ((Get-PestoConfigurationSignature $cfgNew) -eq (Get-PestoConfigurationSignature $back))
    $bad=$raw|ConvertFrom-Json;$bad.POLICY|Add-Member -NotePropertyName _note -NotePropertyValue 'x'
    Check 'Contre-épreuve : un commentaire dans POLICY est refusé (schéma fermé)' (@(Test-CfgValid $bad).Count -gt 0)
}catch{$R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber)}
$R
'RESULTAT {0} reussis, {1} echecs' -f @($R|Where-Object{$_ -like 'PASS*'}).Count,@($R|Where-Object{$_ -notlike 'PASS*'}).Count

# Page Paramètres (08/10/2026) : vrais contrôles de Pesto-Shell.xaml, vraies fonctions Load-SettingsUI / Build-CfgFromUI /
# Build-PestoPolicyFromUI / Test-CfgValid / Get-PestoConfigurationSignature. Windows PowerShell 5.1, STA, sans bureau.
param([string]$Wad='C:\PestoTest\wad',[string]$Model='C:\PestoTest-run\cfg.modele-complet.json')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Data
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);if(@($e).Count){throw "Syntaxe $File : $($e[0].Message) @ $($e[0].Extent.StartLineNumber)"}
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('Assert-PestoClosedObject','Test-PestoPropertyPresent','Get-PestoStableHash'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoDnsName','Test-PestoOUPath'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoDomainFromDN'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Convert-Value-TF','ToTF','New-KvTable','ConvertTo-PestoOrderedMap','Set-PestoMapValue'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy'))))

. ([scriptblock]::Create((Import-Fn 'Pesto-Configuration.ps1' @('ConvertTo-PestoCanonicalValue','Get-PestoConfigurationSignature','Test-CfgValid','Load-SettingsUI','Build-PestoPolicyFromUI','Build-CfgFromUI'))))
function Sync-PestoAppearanceControls {};function Update-PestoSharedNameStatus {}
try { & {
    [xml]$x=Get-Content (Join-Path $Wad 'Pesto-Shell.xaml') -Raw -Encoding UTF8
    $Win=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x))
    foreach($n in @('SetTxtDomaine','SetTxtADM','SetTxtPrefixe','SetTxtPreprod','SetTxtBuffer','SetCmbDarkMode','SetChkDirectProd','SetTxtOUScan','SetChkDsreg','SetLblPrefixes','SetGridTags','SetGridOUBase','SetGridOUSite','SetChkGUI','SetChkSim','SetChkODM','SetChkWOU','SetChkBVA','SetChkGOD','SetLblStatus',
        'SetTxtCoordRoot','SetBtnCoordPrepare','SetBtnCoordTest','SetLblCoordStatus','SetTxtReserveMinutes','SetChkCoordRequired','SetTxtRandomChoice','SetChkReserveAD','SetChkPrecreated','SetTxtMaxBatch','SetTxtMaxReaders','SetTxtReadAttempts',
        'SetChkClearProtection','SetChkPasswordFallback','SetTxtExcludedNames','SetTxtExcludedOUs','SetTxtExcludedGroups')){
        $c=$Win.FindName($n);if(-not $c){throw "Contrôle absent : $n"};Set-Variable -Name $n -Value $c -Scope Script
    }
    Check 'Tous les nouveaux contrôles existent dans Pesto-Shell.xaml' $true
    function Read-Model {Get-Content $Model -Raw -Encoding UTF8|ConvertFrom-Json}
    $script:CFG=Read-Model
    Load-SettingsUI
    Check 'Chargement : dossier partagé' ($SetTxtCoordRoot.Text -eq '\\serveur\partage\Pesto') $SetTxtCoordRoot.Text
    Check 'Chargement : limites et choix' ($SetTxtMaxBatch.Text -eq '200' -and $SetTxtMaxReaders.Text -eq '4' -and $SetTxtReadAttempts.Text -eq '2' -and $SetTxtRandomChoice.Text -eq '0' -and $SetTxtReserveMinutes.Text -eq '15') ''
    Check 'Chargement : cases' (-not $SetChkReserveAD.IsChecked -and -not $SetChkPrecreated.IsChecked -and -not $SetChkCoordRequired.IsChecked -and $SetChkClearProtection.IsChecked) ''
    Check 'Chargement : exclusions, une par ligne' ($SetTxtExcludedNames.Text -eq 'P123456*SRV*') $SetTxtExcludedNames.Text
    # Enregistrer sans rien changer : valide, même signature (aucun redémarrage demandé).
    $same=Build-CfgFromUI;$sameObj=($same|ConvertTo-Json -Depth 20)|ConvertFrom-Json
    Check 'Sans changement : configuration valide' (@(Test-CfgValid $sameObj).Count -eq 0) (@(Test-CfgValid $sameObj) -join ' | ')
    Check 'Sans changement : pas de redémarrage (signature identique)' ((Get-PestoConfigurationSignature $sameObj) -eq (Get-PestoConfigurationSignature $script:CFG))
    # Modifications dans l'interface.
    $SetTxtRandomChoice.Text='5';$SetChkReserveAD.IsChecked=$true;$SetTxtReserveMinutes.Text='30';$SetTxtCoordRoot.Text='\\srv2\coord\Pesto'
    $SetTxtExcludedOUs.Text="OU=Serveurs,DC=example,DC=local`r`n`r`n  OU=Kiosques,DC=example,DC=local  "
    $SetChkClearProtection.IsChecked=$false;$SetChkPrecreated.IsChecked=$true
    $built=(Build-CfgFromUI|ConvertTo-Json -Depth 20)|ConvertFrom-Json
    $p=$built.POLICY
    Check 'Enregistré : types JSON exacts (nombres, booléens, texte)' ($p.RandomNameChoice -is [int] -and $p.RandomNameChoice -eq 5 -and $p.NameReservationMinutes -eq 30 -and $p.ReserveNamesInAD -is [bool] -and $p.ReserveNamesInAD -and $p.AllowPrecreatedJoin -and $p.CoordinationRoot -eq '\\srv2\coord\Pesto') ($p|ConvertTo-Json -Compress)
    Check 'Enregistré : exclusions nettoyées (2 OU)' (@($p.ExcludedOUs).Count -eq 2 -and @($p.ExcludedOUs)[1] -eq 'OU=Kiosques,DC=example,DC=local') (@($p.ExcludedOUs) -join ';')
    Check 'Enregistré : liste d''un seul élément gardée en liste' (@($p.ExcludedNames).Count -eq 1 -and ($built|ConvertTo-Json -Depth 20) -match '"ExcludedNames":\s*\[') ''
    Check 'Enregistré : protection AD décochée → "false"' ((@($built.CONF)[0]).ClearProtectionOnMove -eq 'false')
    Check 'Enregistré : configuration valide' (@(Test-CfgValid $built).Count -eq 0) (@(Test-CfgValid $built) -join ' | ')
    Check 'Vrai changement : redémarrage demandé (signature différente)' ((Get-PestoConfigurationSignature $built) -ne (Get-PestoConfigurationSignature $script:CFG))
    # Valeurs invalides : signalées par la validation, rien d'enregistré en silence.
    $SetTxtMaxBatch.Text='abc';$SetTxtRandomChoice.Text='99'
    $bad=(Build-CfgFromUI|ConvertTo-Json -Depth 20)|ConvertFrom-Json;$errs=@(Test-CfgValid $bad)
    Check 'Valeur illisible ou hors borne : erreur affichée' (@($errs|Where-Object{$_ -like 'Limite invalide*'}).Count -ge 1) ($errs -join ' | ')
    # Ancien fichier sans POLICY : enregistrement sans changement = pas de redémarrage.
    $legacy=Read-Model;$legacy.PSObject.Properties.Remove('POLICY');$script:CFG=$legacy
    Load-SettingsUI
    $b2=(Build-CfgFromUI|ConvertTo-Json -Depth 20)|ConvertFrom-Json
    Check 'Ancien fichier sans POLICY : défauts affichés, pas de redémarrage à l''enregistrement' ($SetTxtMaxBatch.Text -eq '200' -and (Get-PestoConfigurationSignature $b2) -eq (Get-PestoConfigurationSignature $legacy)) ''
} *>&1 | ForEach-Object { if($_ -is [Management.Automation.ErrorRecord]){$script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber)} } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
'RESULTAT {0} reussis, {1} echecs' -f @($script:R|Where-Object{$_ -like 'PASS*'}).Count,@($script:R|Where-Object{$_ -notlike 'PASS*'}).Count

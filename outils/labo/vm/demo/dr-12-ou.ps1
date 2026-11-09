# Démo réelle : ferme les fenêtres de Pesto, renomme l'OU de recette « Pesto-Demo » en « Departement 111301 » (nom neutre
# visible dans les emplacements des captures), avec le compte de recette de la session (droits délégués sur cette OU).
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
& {
  try {
    $lot = Wait-Fenetre 'Préparer un lot' 3; if ($lot) { $f = Find-Element $lot 'Fermer' 'Button'; if ($f) { Invoke-Element $f | Out-Null; Start-Sleep -Seconds 2; 'lot fermé' } }
    $w = Wait-Fenetre 'Pesto 1\.0' 5
    if ($w) { for ($k=0;$k -lt 4;$k++){ Send-Touches $w '{ESC}'; Start-Sleep -Milliseconds 800 }; $p=$null; if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern,[ref]$p)) { $p.Close(); 'Pesto fermé' } }
    Start-Sleep -Seconds 8
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile('C:\PestoDemo\wad\Pesto-Safety.ps1',[ref]$t,[ref]$e)
    foreach($n in 'Assert-PestoPlainPath','Import-PestoADModule'){ $f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true)); . ([scriptblock]::Create($f[0].Extent.Text)) }
    Import-PestoADModule -ADModulePath 'C:\PestoDemo\wad\ActiveDirectory.psd1'
    $laboDom = $env:PESTO_LABO_DOMAINE
    if (-not $laboDom) { throw 'Domaine du labo absent : passer -Domain ou PESTO_LABO_DOMAINE.' }
    $laboDn = 'DC=' + (($laboDom -split '\.') -join ',DC=')
    $disc = [string](Get-ADDomainController -Discover -DomainName $laboDom -Writable -Service ADWS -ForceDiscover).HostName[0]
    $pdc = ([string](Get-ADDomain -Server $disc).PDCEmulator).TrimEnd('.')
    $ou = Get-ADOrganizationalUnit -Server $pdc -LDAPFilter '(ou=Pesto-Demo)' -SearchBase ('OU=ADCC-Lab,' + $laboDn) -SearchScope OneLevel
    if ($ou) { Rename-ADObject -Server $pdc -Identity $ou.ObjectGUID -NewName 'Departement 111301'; 'OU renommée : ' + (Get-ADOrganizationalUnit -Server $pdc -Identity $ou.ObjectGUID).DistinguishedName }
    else { 'OU Pesto-Demo absente : ' + ((Get-ADOrganizationalUnit -Server $pdc -Filter * -SearchBase ('OU=ADCC-Lab,' + $laboDn) -SearchScope OneLevel | ForEach-Object Name) -join ', ') }
  } catch { "ÉCHEC : $($_.Exception.Message)" }
} *> "$D\12-ou.txt"

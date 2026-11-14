"""Nom pris par un autre poste du banc (07/10/2026, décision de David : proposer le suivant, confirmation en un clic)."""
from pathlib import Path
import re
import unittest

WAD = Path(__file__).resolve().parents[1] / 'wad'


def body(file, name):
    text = (WAD / file).read_text('utf-8-sig')
    m = re.search(r'(?m)^function ' + re.escape(name) + r'\b', text)
    if not m:
        return ''
    nxt = re.search(r'(?m)^function ', text[m.end():])
    return text[m.start():m.end() + nxt.start()] if nxt else text[m.start():]


class TakenNameTests(unittest.TestCase):
    def test_taken_names_never_proposed_again(self):
        self.assertIn('$script:PestoTakenNames.Contains($name)', body('Pesto-Join.ps1', 'Get-PestoJoinNameCandidates'))
        self.assertIn('$script:PestoTakenNames.Contains([string]$n)', body('Pesto-Core.ps1', 'Update-NameList'))

    def test_join_conflict_proposes_next_and_rechecks(self):
        check = body('Pesto-Join.ps1', 'Complete-PestoJoinCheck')
        self.assertRegex(check, r'(?s)Test-PestoJoinNameTaken \$Result\).*Select-PestoJoinNextName.*Request-PestoJoinAutoNextCheck')
        done = body('Pesto-Join.ps1', 'Complete-PestoJoinExecution')
        self.assertIn('Test-PestoJoinNameTaken -Check $Result.Check -Code $code', done)
        self.assertIn('Select-PestoJoinNextName', done)

    def test_direct_conflict_proposes_next_and_rechecks(self):
        pre = body('Pesto-Direct.ps1', 'Complete-PestoDirectPreflight')
        self.assertRegex(pre, r"(?s)Nom cible déjà présent dans AD.*Select-PestoDirectNextName")
        act = body('Pesto-Direct.ps1', 'Complete-PestoDirectAction')
        self.assertRegex(act, r'(?s)\$code -eq 69.*Select-PestoDirectNextName')

    def test_next_name_always_rechecked_and_confirmed(self):
        # La relance passe par le contrôle complet, qui redemande la confirmation : jamais d'exécution directe.
        for file, tick, start in (('Pesto-Join.ps1', 'Invoke-PestoJoinAutoNextTick', 'Start-PestoJoinCheck'),
                                  ('Pesto-Direct.ps1', 'Invoke-PestoDirectAutoNextTick', 'Start-PestoDirectPreflight')):
            b = body(file, tick)
            self.assertIn(start, b)
            self.assertNotRegex(b, r'Invoke-PestoJoinExecute|Start-PestoDirectAction|AddToDomain|RenameComputer')
        self.assertIn('Confirm-YesNo', body('Pesto-Join.ps1', 'Complete-PestoJoinCheck'))
        self.assertIn('Confirm-YesNo', body('Pesto-Direct.ps1', 'Complete-PestoDirectPreflight'))

    def test_discovered_dc_kept_no_pdc_switch(self):
        # Décision de David du 08/10 (réseau réel à plusieurs contrôleurs) : « remet comme avant […] le multi contrôleur
        # fout la merde ». La bascule de tous les postes vers l'émulateur PDC (07/10) est retirée : le contrôleur découvert
        # est gardé. Seul reste le cas historique où le « DC » n'est que le nom du domaine (FQDN réel requis par Add-Computer).
        text = (WAD / 'Pesto-Directory.ps1').read_text('utf-8-sig')
        self.assertNotIn('Set-PestoDCRole', text)
        self.assertNotIn('$adpPdc', text)
        self.assertNotIn('DCRole', text)
        self.assertIn("if (($dc -ieq $domain -or $dc -notmatch '\\.') -and $d.PDCEmulator) {", text)
        self.assertNotIn('Set-PestoDCRole', (WAD / 'Pesto-Authentication.ps1').read_text('utf-8-sig'))

    def test_bounded_retries(self):
        self.assertIn('-gt 5', body('Pesto-Join.ps1', 'Select-PestoJoinNextName'))
        self.assertIn('-gt 5', body('Pesto-Direct.ps1', 'Select-PestoDirectNextName'))



    def test_series_read_in_ad_when_name_taken(self):
        # 08/10 (David : « il cherche plusieurs postes avant de trouver le bon ») : un nom pris renvoie toute sa série,
        # lue dans tout le domaine en une requête ; le nom suivant proposé est le premier numéro réellement libre.
        join = body('Pesto-Join.ps1', 'Get-PestoJoinPreflight')
        self.assertRegex(join, r"(?s)if\(\$nameBlocked -and \(ConvertTo-PestoNameParts \$name\)\).*New-PestoNameLdapPattern.*-SearchBase \$domain\.DistinguishedName -SearchScope Subtree")
        self.assertIn('SeriesTaken=$seriesTaken;', join)
        self.assertRegex(join, r'(?s)try\{\s*\$seriesTaken=.*\}catch\{\$seriesTaken=@\(\)\}')
        pre = body('Pesto-Core.ps1', 'Invoke-PestoReadOnlyPreflight')
        self.assertRegex(pre, r"(?s)if\(\$taken\.Count\)\{.*\$seriesTaken=@\(Get-ADComputer.*throw \"Nom cible déjà présent dans AD")
        self.assertIn('SeriesTaken=$seriesTaken;', pre)
        add = body('Pesto-Join.ps1', 'Add-PestoTakenNames')
        self.assertIn('Test-PestoGeneratedComputerName $n', add)
        self.assertIn('Add-PestoTakenNames @($Result.SeriesTaken)', body('Pesto-Join.ps1', 'Complete-PestoJoinCheck'))
        self.assertIn('Add-PestoTakenNames @($Result.Check.SeriesTaken)', body('Pesto-Join.ps1', 'Complete-PestoJoinExecution'))
        self.assertIn('Add-PestoTakenNames @($r.SeriesTaken)', body('Pesto-Direct.ps1', 'Complete-PestoDirectPreflight'))

    def test_name_generation_covers_names_inventory(self):
        self.assertIn('foreach ($c in (Get-PestoKnownComputers))', body('Pesto-Core.ps1', 'Get-ComputersForNameGeneration'))
        source=body('Pesto-Directory.ps1', 'Get-PestoKnownComputers')
        self.assertIn('@($script:Computers)+@($script:ComputersNoms)+@(Get-PestoSiteLookupItems)', source)
        self.assertIn('Select-PestoUniqueComputers', source)

    def test_inventory_arrival_does_not_stop_the_chain(self):
        # 08/10 (« il cherche 3 postes et abandonne, il faut le relancer ») : l'inventaire arrivé pendant un contrôle
        # recalcule la liste ; le contrôle est relancé sur le nom proposé au lieu de s'arrêter sur « Contrôle périmé ».
        check = body('Pesto-Join.ps1', 'Complete-PestoJoinCheck')
        self.assertIn("if($Context.Generation -ne $script:JoinGeneration){Set-PestoJoinMessage 'Contrôle périmé'", check)
        self.assertRegex(check, r'(?s)if\(\$Result\.Key -ne \(Get-PestoJoinPlanKey.*JoinAutoRecheck -le 3.*Request-PestoJoinAutoNextCheck')
        # Le succès remet les deux compteurs à zéro ; la confirmation reste après le contrôle.
        self.assertIn('$script:JoinAutoNext=0;$script:JoinAutoRecheck=0', check)

    def test_manual_click_resets_counters(self):
        start = body('Pesto-Join.ps1', 'Start-PestoJoinCheck')
        self.assertIn('[switch]$Auto', start)
        self.assertIn('if(-not $Auto){$script:JoinAutoNext=0;$script:JoinAutoRecheck=0}', start)
        self.assertIn('-Auto', body('Pesto-Join.ps1', 'Invoke-PestoJoinAutoNextTick'))
        direct = body('Pesto-Direct.ps1', 'Start-PestoDirectPreflight')
        self.assertIn('if(-not $Auto){$script:DirectAutoNext=0}', direct)
        self.assertIn('-Auto', body('Pesto-Direct.ps1', 'Invoke-PestoDirectAutoNextTick'))


if __name__ == '__main__':
    unittest.main(verbosity=2)

"""« Vérification requise » expliqué et actionnable (08/10/2026, David : « blocage sur vérification requise alors que tous
les champs sont remplis en renommage... teste en mise domaine »)."""
from pathlib import Path
import re
import unittest

WAD = Path(__file__).resolve().parents[1] / 'wad'


def body(file, name):
    text = (WAD / file).read_text('utf-8-sig').replace('\r\n', '\n')
    m = re.search(r'(?m)^function ' + re.escape(name) + r'\b', text)
    if not m:
        return ''
    nxt = re.search(r'(?m)^function ', text[m.end():])
    return text[m.start():m.end() + nxt.start()] if nxt else text[m.start():]


class BlockedStateTests(unittest.TestCase):
    def test_each_cause_has_its_text(self):
        ctx = body('Pesto-UXFlow.ps1', 'Get-PestoPrimaryContext')
        for text in ('fermez puis relancez Pesto', 'La jonction de ce PC nécessite encore un redémarrage ou son état reste indéterminé',
                     'Une ancienne exécution doit être vérifiée', 'Une ligne de la file est en cours de modification',
                     'La dernière opération sur ce poste attend une vérification'):
            self.assertIn(text, ctx)
        self.assertIn('-BlockedHint $blockedHint -BlockedAction $blockedAction', ctx)
        self.assertIn("Le suivi complémentaire d''une commande terminée reste facultatif", ctx)
        self.assertNotIn('puis vous consignez', ctx)

    def test_blocked_button_opens_the_review(self):
        step = body('Pesto-UXFlow.ps1', 'Get-PestoPrimaryStep')
        self.assertIn("if($BlockedAction -ne 'None' -and -not $ReadOnly)", step)
        self.assertIn("'ReviewJoin'{'Vérifier la jonction'}", step)
        act = body('Pesto-UXFlow.ps1', 'Invoke-PestoPrimaryAction')
        self.assertIn("'ReviewJoin' {Invoke-PestoJoinReviewClick $Sender $EventArgs;Update-AddButton;Update-PestoSuiteUI}", act)
        self.assertIn("'Interventions' {Show-PestoInterventions;Update-AddButton;Update-PestoSuiteUI}", act)
        self.assertIn("'ReviewDirect' {Show-PestoPostState -Mode Direct;Update-AddButton;Update-PestoSuiteUI}", act)
        # La vérification reste explicite : aucune consignation ni levée de verrou dans le parcours principal.
        self.assertNotRegex(act + step, r'JoinLocked\s*=|MutationUncertain\s*=|DirectLocked\s*=|Confirm-PestoInterventionObservation')

    def test_save_without_change_no_restart(self):
        sig = body('Pesto-Configuration.ps1', 'Get-PestoConfigurationSignature')
        self.assertIn("if(-not $entra.Count){$c['EntraPolicy']='HybridOnly'}", sig)
        # Le moteur applique HybridOnly quand la valeur manque : même sens, même signature.
        self.assertIn("$script:EntraPolicy=if($Request.EntraPolicy -in @('HybridOnly','Disabled')){[string]$Request.EntraPolicy}else{'HybridOnly'}",
                      (WAD / 'Pesto-Core.ps1').read_text('utf-8-sig'))


if __name__ == '__main__':
    unittest.main(verbosity=2)

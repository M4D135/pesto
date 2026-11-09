"""Démo réelle du 08/10/2026 sur l'AD du labo : deux défauts trouvés.

1. Un reçu de jonction historique écrit avec un autre préfixe (cfg.json changé depuis, autre département) était jugé
   invalide : toute opération sur ce PC était refusée. Le nom du reçu se valide sur sa structure, pas sur le préfixe du jour.
2. Ce refus, prononcé avant toute commande, rendait 97 (incertain) et enregistrait l'opération comme incertaine, ce qui
   bloquait à son tour la suite. Il rend 96 (non lancé).
"""
from pathlib import Path
import re
import unittest

WAD = Path(__file__).resolve().parents[1] / 'wad'


class StoredStateGuardTests(unittest.TestCase):
    def test_historical_join_receipt_name_ignores_current_prefix(self):
        text = (WAD / 'Pesto-JoinRecovery.ps1').read_text('utf-8-sig')
        body = text[text.index('function Assert-PestoJoinReceiptData'):text.index('function Test-PestoJoinIntervention')]
        self.assertIn("Test-PestoGeneratedComputerName $Receipt.NewName -Prefix ''", body)
        self.assertNotRegex(body, r"Test-PestoGeneratedComputerName \$Receipt\.NewName\)")

    def test_historical_join_intervention_and_import_ignore_current_prefix(self):
        recovery = (WAD / 'Pesto-JoinRecovery.ps1').read_text('utf-8-sig')
        body = recovery[recovery.index('function Test-PestoJoinIntervention'):recovery.index('function Assert-PestoJoinEvidence')]
        self.assertIn("Test-PestoGeneratedComputerName ([string]$p.Nouveau_Nom) -Prefix ''", body)
        old = (WAD / 'Pesto-Recovery.ps1').read_text('utf-8-sig')
        self.assertIn("Test-PestoGeneratedComputerName ([string]$row.Nouveau_Nom) -Prefix ''", old)

    def test_guard_refusal_before_launch_is_96(self):
        core = (WAD / 'Pesto-Core.ps1').read_text('utf-8-sig')
        match = re.search(r"try\{Assert-PestoStoredMutationReady[^\n]*\}catch\{\s*(?:#[^\n]*\n\s*)?return \[pscustomobject\]@\{Action=\(New-ActionResult (\d+) ", core)
        self.assertIsNotNone(match)
        self.assertEqual('96', match.group(1))

    def test_parser_accepts_other_prefix_when_none_required(self):
        contracts = (WAD / 'Pesto-Contracts.ps1').read_text('utf-8-sig')
        self.assertIn("($Prefix -and $m.Groups['Prefix'].Value -cne $Prefix)", contracts)


if __name__ == '__main__':
    unittest.main(verbosity=2)

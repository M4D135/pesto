import os
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


def read(name):
    path = os.path.join(WAD, name)
    if not os.path.exists(path):
        raise AssertionError('Fichier source introuvable : ' + path)
    with open(path, 'r', encoding='utf-8-sig') as f:
        return f.read()


class TestSparkT079(unittest.TestCase):
    def test_decision_offers_delayed_read_without_repair(self):
        content = read('Pesto-JoinRecovery.ps1')
        self.assertIn('$d.RetryAfterSec=30', content)
        self.assertIn('relire dans 30 s. Aucune réparation automatique.', content)
        self.assertNotIn('-Repair', content)

    def test_button_is_wired_to_a_single_read(self):
        content = read('Pesto-Inspection.ps1')
        self.assertIn('x:Name="StateRetryLater" Content="Relire dans 30 s"', content)
        self.assertIn("'StateRetryLater' {Start-PestoStateDelayedRead}", content)
        self.assertIn('Get-PestoStateRetryDelay $ui.Decision', content)
        start = content.find('function Invoke-PestoStateDelayedTick')
        end = content.find('\n}\n', start)
        self.assertGreater(start, -1)
        tick = content[start:end]
        # Le minuteur ne relance que la lecture Windows/AD.
        self.assertIn('Start-PestoPostStateRead', tick)
        for forbidden in ('Apply-Pesto', 'Confirm-Pesto', 'Start-PestoRecovery', 'Start-PestoJoin'):
            self.assertNotIn(forbidden, tick)
        self.assertNotIn('-Repair', content)
        self.assertNotIn('sc_reset', content)
        # La santé locale ne porte pas de champ de relance inutilisé.
        self.assertNotIn('RetryAfterSec=0', content)


if __name__ == '__main__':
    unittest.main()

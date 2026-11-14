import os
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


def read(name):
    path = os.path.join(WAD, name)
    if not os.path.exists(path):
        raise AssertionError('Fichier source introuvable : ' + path)
    with open(path, 'r', encoding='utf-8-sig') as f:
        return f.read()


class TestSparkT113(unittest.TestCase):
    def test_perf_event_in_names(self):
        content = read('Pesto-Names.ps1')
        self.assertIn('PestoPerfLastLog', content, 'Limitation par opération absente')
        self.assertIn('TotalSeconds -ge 1', content, 'Limitation à un événement par seconde absente')
        self.assertIn("-NotePropertyName 'Kind' -NotePropertyValue 'perf'", content)
        self.assertIn('Write-PestoStructuredEvent', content)
        for field in ("'Ms'", "'WaitMs'", "'WorkMs'"):
            self.assertIn('-NotePropertyName ' + field, content)

    def test_perf_event_dc_is_domain_controller(self):
        # Le champ DC désigne le contrôleur utilisé, jamais le poste du technicien.
        content = read('Pesto-Names.ps1')
        self.assertIn("-NotePropertyName 'DC' -NotePropertyValue ([string]$script:DC)", content)
        self.assertNotIn('[System.Environment]::MachineName', content)

    def test_perf_events_classified_in_diagnostics(self):
        content = read('Pesto-Support.ps1')
        self.assertIn("'(?i)(perf|performance)' {return 'Performance'}", content)


if __name__ == '__main__':
    unittest.main()

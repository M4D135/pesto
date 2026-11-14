import os
import re
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


class TestSparkD03(unittest.TestCase):
    def setUp(self):
        self.path = os.path.join(WAD, 'Pesto-EngineContracts.ps1')
        if not os.path.exists(self.path):
            self.fail('Fichier source introuvable : ' + self.path)
        with open(self.path, 'r', encoding='utf-8-sig') as f:
            self.content = f.read()

    def test_policy_local_only(self):
        pattern = r"'Policy'\s*\{\s*\$result\s*=\s*ConvertTo-PestoPolicy\s+\$data\s+-LocalOnly\s*\}"
        self.assertTrue(re.search(pattern, self.content), 'La branche Policy doit utiliser -LocalOnly')

    def test_no_policy_add_member(self):
        self.assertIsNone(re.search(r"Add-Member\s+NoteProperty\s+Policy\b", self.content))

    def test_random_name_migration(self):
        # Remove-Member n'existe pas en PowerShell : la clé historique est retirée par PSObject.Properties.Remove.
        self.assertNotIn('Remove-Member', self.content)
        self.assertIn("PSObject.Properties.Remove('RandomNameChoice')", self.content)

    def test_save_backup_reuse(self):
        self.assertIn('Sauvegarde existante différente de la source', self.content)
        self.assertIn('ComputeHash', self.content)


if __name__ == '__main__':
    unittest.main()

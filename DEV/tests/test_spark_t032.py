import os
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


class TestSparkT032(unittest.TestCase):
    def setUp(self):
        path = os.path.join(WAD, 'Pesto-EngineContracts.ps1')
        if not os.path.exists(path):
            self.fail('Fichier source introuvable : ' + path)
        with open(path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
        start = content.find('function Save-PestoSchemaMigration')
        end = content.find('function New-PestoReadCoordinator', start)
        self.assertGreater(start, -1)
        self.assertGreater(end, start)
        self.body = content[start:end]

    def test_fileinfo_check_before_read(self):
        idx_check = self.body.find('$fileInfo.Length -gt 1MB')
        idx_read = self.body.find('[IO.File]::ReadAllBytes($SourcePath)')
        self.assertGreater(idx_check, -1)
        self.assertGreater(idx_read, -1)
        self.assertLess(idx_check, idx_read, 'La taille est contrôlée avant la lecture')

    def test_single_strict_read_and_bom_strip(self):
        self.assertNotIn('[IO.File]::ReadAllText', self.body)
        for marker in ('0xEF', '0xBB', '0xBF'):
            self.assertIn(marker, self.body)
        # Décodage strict : un octet invalide est refusé, jamais remplacé par U+FFFD.
        self.assertIn('[Text.UTF8Encoding]::new($false, $true)).GetString(', self.body)
        self.assertNotIn('[Text.Encoding]::UTF8.GetString', self.body)

    def test_backup_reuse_logic(self):
        self.assertIn('[IO.File]::Exists($backup)', self.body)
        self.assertIn('Sauvegarde existante différente de la source', self.body)
        self.assertIn('[IO.File]::Move($temporary, $backup)', self.body)


if __name__ == '__main__':
    unittest.main()

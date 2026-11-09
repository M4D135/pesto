import os
import re
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


class TestSparkE04AtomicWriteRetry(unittest.TestCase):
    """Le nombre réel de tentatives est exécuté par tests/Run-Engine120Tests.ps1."""

    def setUp(self):
        path = os.path.join(WAD, 'Pesto-Core.ps1')
        if not os.path.exists(path):
            self.fail('Fichier source introuvable : ' + path)
        with open(path, 'r', encoding='utf-8-sig') as f:
            content = f.read().replace('\r\n', '\n')
        match = re.search(r'function Write-PestoAtomicText \{.*?\n\}\n', content, re.DOTALL)
        self.assertIsNotNone(match)
        self.body = match.group(0)

    def test_only_sharing_or_lock_violation_retried(self):
        self.assertIn('-2147024864', self.body)
        self.assertIn('-2147024863', self.body)
        self.assertIn('$delays=@(100,300,900)', self.body)
        self.assertIn('$attempt -ge $delays.Count){throw}', self.body)

    def test_hook_is_test_only(self):
        self.assertIn("réservé aux tests", self.body)
        with open(os.path.join(WAD, 'Pesto-Core.ps1'), 'r', encoding='utf-8-sig') as f:
            content = f.read()
        self.assertEqual(content.count('PestoFileReplaceHook'), self.body.count('PestoFileReplaceHook'),
                         'Le point d\'injection ne doit être défini nulle part en production')

    def test_destination_never_deleted(self):
        self.assertNotIn('[IO.File]::Delete($full)', self.body)


if __name__ == '__main__':
    unittest.main()

import os
import re
import unittest

WAD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'wad')


class TestSparkW4RT013(unittest.TestCase):
    def test_configuration_migration_logic(self):
        """La migration 'Configuration' normalise POLICY en place, sans fusion GPO ni clé 'Policy'.
        Le comportement est exécuté par tests/Run-Engine120Tests.ps1."""
        path = os.path.join(WAD, 'Pesto-EngineContracts.ps1')
        if not os.path.exists(path):
            self.fail('Fichier source introuvable : ' + path)
        with open(path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
        block = re.search(r"'Configuration'\s*\{(.*?)\n        \}", content, re.DOTALL)
        self.assertIsNotNone(block, "Bloc 'Configuration' non trouvé dans ConvertTo-PestoSchemaMigration")
        block = block.group(1)
        self.assertIn('ConvertTo-PestoPolicy $result.POLICY -LocalOnly', block)
        self.assertIsNone(re.search(r"\$result\s*\|\s*Add-Member\s+NoteProperty\s+Policy\b", block))
        self.assertIn("[void]$result.POLICY.PSObject.Properties.Remove('RandomNameChoice')", block)
        self.assertNotIn('Remove-Member', block)


if __name__ == '__main__':
    unittest.main()

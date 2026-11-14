import unittest
from pathlib import Path

WAD = Path(__file__).resolve().parents[1] / 'wad'


def read(name):
    path = WAD / name
    if not path.is_file():
        raise AssertionError('Fichier source introuvable : ' + str(path))
    return path.read_text(encoding='utf-8-sig')


class TestSparkT010(unittest.TestCase):
    def test_fallback_objects_have_utc_and_opid(self):
        """Les objets de repli d'Invoke-Pesto.ps1 et d'Invoke-PestoAutoJoin.ps1 portent Utc et OperationId,
        et celui d'Invoke-PestoAutoJoin.ps1 porte aussi Metadata."""
        content1 = read('Invoke-Pesto.ps1')
        self.assertIn("Utc=[DateTime]::UtcNow.ToString('o')", content1, "Invoke-Pesto.ps1 doit avoir Utc dans le fallback")
        self.assertIn("OperationId=''", content1, "Invoke-Pesto.ps1 doit avoir OperationId dans le fallback")

        content2 = read('Invoke-PestoAutoJoin.ps1')
        self.assertIn("Utc=[DateTime]::UtcNow.ToString('o')", content2, "Invoke-PestoAutoJoin.ps1 doit avoir Utc dans le fallback")
        self.assertIn("OperationId=''", content2, "Invoke-PestoAutoJoin.ps1 doit avoir OperationId dans le fallback")
        self.assertIn("Metadata=$null", content2, "Invoke-PestoAutoJoin.ps1 doit avoir Metadata dans le fallback")

    # Les blocs catch d'Invoke-PestoUnattendedOperation (Pesto-Enterprise.ps1) et d'Invoke-PestoUnattendedJoin
    # (Pesto-Automation.ps1) ne transmettent toujours ni OperationId ni Metadata : cette partie de T010 n'est pas
    # implémentée (voir docs/implementation/LOT_SPARK_FILTRE2.md). Aucun test ne prétend le contraire.


if __name__ == '__main__':
    unittest.main()

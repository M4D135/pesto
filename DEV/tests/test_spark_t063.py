import unittest
from pathlib import Path

JOURNAL = Path(__file__).resolve().parents[1] / 'wad' / 'Pesto-Journal.ps1'


def read_journal():
    if not JOURNAL.is_file():
        raise AssertionError('Fichier source introuvable : ' + str(JOURNAL))
    return JOURNAL.read_text(encoding='utf-8-sig')


class TestPestoAuditRollover(unittest.TestCase):
    """Contrôle statique ; le passage de minuit est exécuté par tests/Run-AuditPathTests.ps1."""

    def test_rollover_logic_present(self):
        content = read_journal()
        self.assertIn("Suite dans Pesto_", content, "Message de transition manquant")
        self.assertIn("Suite du journal du", content, "Message de reprise manquant")
        self.assertIn("Initialize-AuditLog", content, "Réinitialisation du journal manquante")
        self.assertIn("$script:PestoAuditWriter.Close(2000)", content, "Fermeture du writer manquante")
        self.assertIn("$currentDateStr -ne $fileDateStr", content, "Comparaison de date manquante")
        # La perte constatée avant la bascule reste bloquante (banc réel : Run-AuditPathTests.ps1).
        self.assertIn("if($script:PestoAuditLost){return $false}", content, "Barrière de perte non persistante")

    def test_clock_injection_support(self):
        content = read_journal()
        self.assertIn("$script:PestoAuditClock", content, "Injection d'horloge non supportée")
        self.assertIn("& $script:PestoAuditClock", content, "Appel de l'horloge injectée manquant")


if __name__ == '__main__':
    unittest.main()

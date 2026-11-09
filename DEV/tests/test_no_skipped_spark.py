"""Aucun test test_spark_* n'est ignoré en silence.

La découverte est rejouée depuis ce dossier ; seul un saut dont la raison commence par « Plateforme » (décorateur
explicite, par exemple un faux exécutable POSIX) est admis. Un fichier source absent doit faire échouer un test,
jamais le transformer en saut.
"""
import unittest
from pathlib import Path

TESTS = Path(__file__).resolve().parent


class SparkTestsNeverSkip(unittest.TestCase):
    def test_no_spark_test_is_skipped(self):
        suite = unittest.TestLoader().discover(str(TESTS), pattern='test_spark_*.py', top_level_dir=str(TESTS))
        result = unittest.TestResult()
        suite.run(result)
        self.assertGreater(result.testsRun, 50)
        silent = [(str(test), reason) for test, reason in result.skipped if not str(reason).startswith('Plateforme')]
        self.assertEqual(silent, [])


if __name__ == '__main__':
    unittest.main()

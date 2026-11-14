"""Portable check of the root .cmd launchers (text only; the Windows run is in preuves/)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
# call refait une passe d'expansion des % et double les ^ : un dossier « a^b » ou « c%PATH%d » casse le lancement.
CALL_DP0 = re.compile(r'(?im)^\s*call\s+"%~dp0')


class CmdLauncherTests(unittest.TestCase):
    def test_root_cmd_never_calls_dp0(self):
        bad = [p.name for p in sorted(ROOT.glob('*.cmd')) if CALL_DP0.search(p.read_text('utf-8-sig', errors='replace'))]
        self.assertEqual([], bad)

    def test_compte_ad_transfers_to_pesto_cmd(self):
        text = (ROOT / 'Pesto_COMPTE_AD.cmd').read_text('utf-8-sig')
        self.assertIn('"%~dp0Pesto.cmd" -AskCredential %*', text)
        self.assertIn('DisableDelayedExpansion', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)

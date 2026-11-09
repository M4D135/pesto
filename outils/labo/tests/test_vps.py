"""Local shell contract only: a fake ssh executable prevents any network/VM access."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'mac' / 'vps.sh'


class VpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pesto-vps-local-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.capture = self.root / 'arguments.json'
        ssh = self.root / 'ssh'
        ssh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ['PESTO_TEST_CAPTURE']).write_text(json.dumps(sys.argv[1:]))
sys.stdout.write(os.environ.get('PESTO_TEST_STDOUT', ''))
sys.stderr.write(os.environ.get('PESTO_TEST_STDERR', ''))
sys.exit(int(os.environ.get('PESTO_TEST_EXIT', '0')))
''')
        ssh.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'],
                        PESTO_TEST_CAPTURE=str(self.capture))
        self.source = self.root / 'script avec espaces.ps1'
        self.code = "param()\nWrite-Output 'Échec Objs CLIXML : conservé'\nexit 42\n"
        self.source.write_bytes(self.code.encode('utf-8-sig'))

    def run_script(self, **environment):
        return subprocess.run(['/bin/bash', str(SCRIPT), str(self.source)],
                              env=dict(self.env, **environment), capture_output=True, timeout=10)

    def test_empty_success_remains_success(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b'')

    def test_remote_failure_and_diagnostics_survive(self):
        result = self.run_script(PESTO_TEST_EXIT='42', PESTO_TEST_STDOUT='Objs utiles\n',
                                 PESTO_TEST_STDERR='Erreur CLIXML : accès refusé\n')
        self.assertEqual(result.returncode, 42)
        self.assertEqual(result.stdout.decode(), 'Objs utiles\n')
        self.assertEqual(result.stderr.decode(), 'Erreur CLIXML : accès refusé\n')

    def test_ssh_failure_is_not_masked(self):
        result = self.run_script(PESTO_TEST_EXIT='255', PESTO_TEST_STDERR='Connection refused\n')
        self.assertEqual(result.returncode, 255)
        self.assertEqual(result.stderr, b'Connection refused\n')

    def test_command_preserves_script_bytes_after_bom_removal(self):
        self.assertEqual(self.run_script().returncode, 0)
        arguments = json.loads(self.capture.read_text())
        command, encoded = arguments[-1].rsplit(' ', 1)
        self.assertIn('-NonInteractive -OutputFormat Text -EncodedCommand', command)
        self.assertEqual(base64.b64decode(encoded).decode('utf-16le'), self.code)

    def test_invalid_utf8_stops_before_ssh(self):
        self.source.write_bytes(b'\xff\xfeinvalid')
        self.assertEqual(self.run_script().returncode, 2)
        self.assertFalse(self.capture.exists())

    def test_missing_input_stops_before_ssh(self):
        self.source.unlink()
        self.assertEqual(self.run_script().returncode, 2)
        self.assertFalse(self.capture.exists())


if __name__ == '__main__':
    unittest.main()

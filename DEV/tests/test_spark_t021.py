import unittest
import os

class TestSparkT021(unittest.TestCase):
    def test_environment_reports_dotnet_release(self):
        path = os.path.join(os.path.dirname(__file__), '..', 'tools', 'Test-PestoEnvironment.ps1')
        with open(path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
        self.assertIn('DotNetRelease', content)
        self.assertIn('DotNetVersion', content)
        self.assertIn('ClrVersion', content)
        self.assertIn('533320', content)
        self.assertIn('461808', content)

    def test_integrity_checks_dotnet_floor(self):
        path = os.path.join(os.path.dirname(__file__), '..', 'wad', 'Pesto-Integrity.ps1')
        with open(path, 'r', encoding='utf-8-sig') as f:
            content = f.read()
        self.assertIn('function Get-PestoDotNetFloorStatus', content)
        self.assertIn('Pesto 1.0 exige .NET Framework 4.7.2 ou plus récent', content)
        self.assertIn('461808', content)

if __name__ == '__main__':
    unittest.main()
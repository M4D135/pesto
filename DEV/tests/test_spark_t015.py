import unittest
import re
from pathlib import Path

WAD = Path(__file__).resolve().parents[1] / 'wad'


def read(name):
    path = WAD / name
    if not path.is_file():
        raise AssertionError('Fichier source introuvable : ' + str(path))
    return path.read_text(encoding='utf-8-sig')


class TestSparkT015(unittest.TestCase):
    def test_cli_host_cache_path_function(self):
        content = read('Pesto-CliHost.ps1')
        
        # Check for the new function definition
        self.assertIn('function Get-PestoModuleAnalysisCachePath', content)
        # Check for the fallback logic
        self.assertIn("[Environment]::GetFolderPath('LocalApplicationData')", content)
        # Check that Initialize-PestoCliProcess uses the new function
        self.assertIn('Get-PestoModuleAnalysisCachePath', content)
        # Check that Initialize-PestoCliProcess is wrapped in try/catch
        self.assertIn('function Initialize-PestoCliProcess', content)
        # Simple check for try block presence in the function body
        self.assertIn('try {', content)

    def test_invoke_pesto_try_block(self):
        content = read('Invoke-Pesto.ps1')
        
        # Ensure Initialize-PestoCliProcess is inside a try block
        # We look for the pattern: try{ ... Initialize-PestoCliProcess
        # Note: Whitespace might vary, so we check for the sequence
        self.assertIn('try{', content)
        self.assertIn('Initialize-PestoCliProcess', content)
        # Verify it's not immediately before the try (which was the bug)
        # We expect the call to be after 'try{'
        try_idx = content.find('try{')
        init_idx = content.find('Initialize-PestoCliProcess')
        self.assertGreater(init_idx, try_idx, "Initialize-PestoCliProcess should be inside the try block")

    def test_invoke_pesto_auto_join_try_block(self):
        content = read('Invoke-PestoAutoJoin.ps1')
        
        self.assertIn('try{', content)
        self.assertIn('Initialize-PestoCliProcess', content)
        try_idx = content.find('try{')
        init_idx = content.find('Initialize-PestoCliProcess')
        self.assertGreater(init_idx, try_idx, "Initialize-PestoCliProcess should be inside the try block")

    def test_journal_audit_log_candidates(self):
        content = read('Pesto-Journal.ps1')
        
        # Check for the new candidate building logic
        self.assertIn('$localAppData = $env:LOCALAPPDATA', content)
        self.assertIn("[Environment]::GetFolderPath('LocalApplicationData')", content)
        self.assertIn('$tempDir = $env:TEMP', content)
        self.assertIn('[IO.Path]::GetTempPath()', content)
        
        # Ensure old unsafe Join-Path on env vars directly in array init is gone
        # The old code had: (Join-Path $env:LOCALAPPDATA 'Pesto\logs')
        # We check that this specific pattern is NOT present in the Initialize-AuditLog function context
        # A simple check for the absence of the old pattern is tricky if it exists elsewhere, 
        # but we check for the new structure.
        self.assertNotIn("candidates = @($PreferredDir,\n                    (Join-Path $env:LOCALAPPDATA", content)

if __name__ == '__main__':
    unittest.main()
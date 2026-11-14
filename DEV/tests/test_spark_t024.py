import unittest
import os
import re

class TestSparkT024(unittest.TestCase):
    def test_read_import_file_exists_and_handles_encoding(self):
        # Locate the source file relative to the test file
        # Assuming tests are in DEV/tests and source in DEV/wad
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        source_path = os.path.join(base_dir, 'wad', 'Pesto-BatchTools.ps1')
        
        if not os.path.exists(source_path):
            self.fail(f"Source file not found: {source_path}")

        with open(source_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()

        # 1. Check that Read-PestoImportFile function is defined
        self.assertIn('function Read-PestoImportFile', content, "Read-PestoImportFile function missing")

        # 2. Check for strict UTF8 encoding instantiation
        # Look for UTF8Encoding with throwOnInvalidBytes = true (second arg $true)
        # Pattern: UTF8Encoding]::new($false,$true) or similar
        self.assertIn('[Text.UTF8Encoding]::new($false,$true)', content, "Strict UTF8 encoding not found in Read-PestoImportFile")

        # 3. Check for BOM stripping logic
        # Look for checking 0xEF, 0xBB, 0xBF
        self.assertIn('0xEF', content, "BOM check (0xEF) missing")
        self.assertIn('0xBB', content, "BOM check (0xBB) missing")
        self.assertIn('0xBF', content, "BOM check (0xBF) missing")

        # 4. Check for specific catch block and error message
        self.assertIn('catch [Text.DecoderFallbackException]', content, "Catch for DecoderFallbackException missing")
        
        # Check for the specific French error message
        expected_msg = "Fichier non UTF-8. Dans Excel, choisissez « CSV UTF-8 (délimité par des virgules) », puis importez de nouveau. Aucune ligne ajoutée."
        self.assertIn(expected_msg, content, "Specific French error message missing")

        # 5. Check that Show-PestoMappedImport uses Read-PestoImportFile
        # Find the function Show-PestoMappedImport
        match = re.search(r'function Show-PestoMappedImport.*?(?=function |$)', content, re.DOTALL)
        if match:
            func_body = match.group(0)
            self.assertIn('Read-PestoImportFile', func_body, "Show-PestoMappedImport does not call Read-PestoImportFile")
            # Ensure it doesn't use ReadAllText directly with strict encoding anymore in the file branch
            # The old code was: $text=[IO.File]::ReadAllText($dialog.FileName,[Text.UTF8Encoding]::new($false,$true))
            # We expect this to be replaced by the call to Read-PestoImportFile
            self.assertNotIn('[IO.File]::ReadAllText($dialog.FileName,[Text.UTF8Encoding]::new($false,$true))', func_body, "Old direct ReadAllText call still present in Show-PestoMappedImport")
        else:
            self.fail("Show-PestoMappedImport function not found")

if __name__ == '__main__':
    unittest.main()
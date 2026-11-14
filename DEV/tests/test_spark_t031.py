import unittest
import os

class TestSparkT031(unittest.TestCase):
    def test_chassis_35_36_fixed(self):
        # Locate the source file relative to the test file
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        source_path = os.path.join(base_dir, 'wad', 'Pesto-NameWorkbench.ps1')

        self.assertTrue(os.path.exists(source_path), f"Source file not found: {source_path}")

        with open(source_path, 'r', encoding='utf-8-sig') as f:
            content = f.read()

        # Check that 35 and 36 are in the fixed list
        # The line looks like: elseif(@($Chassis|Where-Object{$_ -in @(3,4,5,6,7,13,15,16,17,23,24,35,36)}).Count)
        
        # Verify presence of 35 and 36 in the array literal for 'Fixe'
        self.assertIn('35', content, "Chassis 35 (Mini PC) missing from fixed list")
        self.assertIn('36', content, "Chassis 36 (Stick PC) missing from fixed list")
        
        # Verify 34 is NOT in the fixed list (should remain unknown/empty type)
        # We check the specific line context to ensure 34 isn't added to the fixed array
        # Simple check: ensure '34' is not in the fixed array string pattern
        # Pattern: @(3,4,5,6,7,13,15,16,17,23,24,35,36)
        # If 34 was added, it would be in there.
        
        # Extract the fixed list line
        import re
        # Match the line containing 'Fixe' and the array
        match = re.search(r'elseif\(@\(\$Chassis\|Where-Object\{\$_ -in @\((.*?)\)\}\)\.Count\)\{\$type=\'Fixe\'', content)
        self.assertTrue(match, "Could not find the fixed chassis check line")
        
        fixed_list_str = match.group(1)
        # Parse integers
        fixed_chassis = [int(x.strip()) for x in fixed_list_str.split(',') if x.strip()]
        
        self.assertIn(35, fixed_chassis, "35 not in fixed list")
        self.assertIn(36, fixed_chassis, "36 not in fixed list")
        self.assertNotIn(34, fixed_chassis, "34 should NOT be in fixed list")
        
        # Verify mobile list is unchanged (optional but good for regression)
        match_mobile = re.search(r'elseif\(@\(\$Chassis\|Where-Object\{\$_ -in @\((.*?)\)\}\)\.Count\)\{\$type=\'Portable\'', content)
        self.assertTrue(match_mobile, "Could not find the portable chassis check line")
        mobile_list_str = match_mobile.group(1)
        mobile_chassis = [int(x.strip()) for x in mobile_list_str.split(',') if x.strip()]
        self.assertNotIn(35, mobile_chassis, "35 should not be in mobile list")
        self.assertNotIn(36, mobile_chassis, "36 should not be in mobile list")

if __name__ == '__main__':
    unittest.main()
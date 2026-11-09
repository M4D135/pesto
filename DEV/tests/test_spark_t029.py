import unittest
import os
import re

class TestSparkT029(unittest.TestCase):
    def setUp(self):
        self.file_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'integrations', 'Pesto.Optional.psm1')
        if not os.path.exists(self.file_path):
            self.fail("Source file not found: " + self.file_path)
        with open(self.file_path, 'r', encoding='utf-8-sig') as f:
            self.content = f.read()

    def test_refused_and_restart_requested_accepted(self):
        # Check that 'Refused' and 'RestartRequested' are in the allowed state list
        # The new list should include them
        self.assertIn("'Refused'", self.content)
        self.assertIn("'RestartRequested'", self.content)
        
        # Ensure the old list which lacked them is replaced or updated correctly
        # We look for the specific block in New-PestoAuditExport
        pattern = r"\$state\s*=\s*\[string\]\$Result\.State.*?if\(\$state\s*-cnotin\s*@\((.*?)\)\)\{throw\s*'Mode\s+ou\s+état\s+audit\s+inconnu\.'\}"
        match = re.search(pattern, self.content, re.DOTALL)
        self.assertIsNotNone(match, "State validation block not found")
        
        states_list = match.group(1)
        self.assertIn("'Refused'", states_list)
        self.assertIn("'RestartRequested'", states_list)
        self.assertIn("'MoveReady'", states_list) # From spec

    def test_prepared_throws_explicitly(self):
        # Check for the explicit throw for Prepared state
        self.assertIn("throw 'Préparation sans identifiant d''opération : rien à auditer.'", self.content)
        
        # Ensure it's inside New-PestoAuditExport
        func_start = self.content.find("function New-PestoAuditExport")
        self.assertNotEqual(func_start, -1)
        func_end = self.content.find("Export-ModuleMember", func_start)
        func_body = self.content[func_start:func_end]
        
        self.assertIn("if($state -ceq 'Prepared')", func_body)

    def test_unknown_state_refused(self):
        # Ensure the validation logic exists
        self.assertIn("if($state -cnotin @(", self.content)
        self.assertIn("throw 'Mode ou état audit inconnu.'", self.content)

    def test_no_sensitive_fields_exported(self):
        # Verify the output object construction doesn't include Message or Password
        # The output is: [pscustomobject][ordered]@{Schema=1;Product='Pesto';OperationId=$id.ToString('D');Mode=[string]$Result.Mode;State=[string]$Result.State;
        # ExitCode=[int]$Result.ExitCode;RestartRequired=[bool]$Result.RestartRequired;ExportedUtc=[DateTime]::UtcNow.ToString('o')}
        
        # Check that 'Message' is not in the output property list
        # We look for the property assignment block
        pattern = r"\[pscustomobject\]\[ordered\]@\{(.*?)\}"
        match = re.search(pattern, self.content, re.DOTALL)
        self.assertIsNotNone(match)
        props = match.group(1)
        self.assertNotIn("Message=", props)
        self.assertNotIn("Password=", props)

if __name__ == '__main__':
    unittest.main()
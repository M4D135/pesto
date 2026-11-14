"""Static check: forbid assignment or foreach iteration on PowerShell automatic variables."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Automatic variables that must not be assigned or used as loop variables in Pesto.
# Case-insensitive match on the variable name after '$'.
AUTOMATIC_VARS = {'matches', 'event', 'args', 'input', 'pwd', 'home'}

# Regex to find assignments: $var = ... or $var += ... or $var -= ...
# We look for '$name' followed by optional whitespace and an assignment operator.
ASSIGN_RE = re.compile(r'\$([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:\+|-)?=', re.IGNORECASE)

# Regex to find foreach loops: foreach($var in ...)
FOREACH_RE = re.compile(r'foreach\s*\(\s*\$([a-zA-Z_][a-zA-Z0-9_]*)\s+in', re.IGNORECASE)


class AutomaticVariableTests(unittest.TestCase):
    def test_no_assignment_to_automatic_variables(self):
        hits = []
        for path in sorted((ROOT / 'wad').rglob('*.ps1')):
            text = path.read_text('utf-8-sig')
            for number, line in enumerate(text.splitlines(), 1):
                # Skip comments
                if line.strip().startswith('#'):
                    continue
                for match in ASSIGN_RE.finditer(line):
                    var_name = match.group(1).lower()
                    if var_name in AUTOMATIC_VARS:
                        hits.append(f'{path.relative_to(ROOT)}:{number} assigns ${var_name}')
        self.assertEqual([], hits)

    def test_no_foreach_over_automatic_variables(self):
        hits = []
        for path in sorted((ROOT / 'wad').rglob('*.ps1')):
            text = path.read_text('utf-8-sig')
            for number, line in enumerate(text.splitlines(), 1):
                # Skip comments
                if line.strip().startswith('#'):
                    continue
                for match in FOREACH_RE.finditer(line):
                    var_name = match.group(1).lower()
                    if var_name in AUTOMATIC_VARS:
                        hits.append(f'{path.relative_to(ROOT)}:{number} foreach over ${var_name}')
        self.assertEqual([], hits)

if __name__ == '__main__':
    unittest.main(verbosity=2)
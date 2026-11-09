"""Static contracts only; execution under Windows PowerShell 5.1 is a separate qualification."""
from pathlib import Path
import re
import unittest

import worker_runspace_static_checks as guard
from ps_lexical import functions


WAD = Path(__file__).resolve().parents[1] / 'wad'


class WorkerRunspaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {name: (WAD / name).read_text('utf-8-sig')
                       for name in (guard.DIRE, guard.AUTH, guard.SAFE)}

    def test_current_contract_and_negative_controls(self):
        sources = self.sources
        self.assertTrue(all(c['status'] == 'PASS' for c in guard.checks(
            sources[guard.DIRE], sources[guard.AUTH], sources[guard.SAFE])))
        for name, file, mutate in guard.MUTATIONS:
            with self.subTest(name=name):
                modified = dict(sources)
                modified[file] = mutate(sources[file])
                self.assertNotEqual(modified[file], sources[file])
                self.assertTrue(any(c['status'] == 'FAIL' for c in guard.checks(
                    modified[guard.DIRE], modified[guard.AUTH], modified[guard.SAFE])))

    def test_braces_in_strings_and_comments_are_not_code(self):
        source = "function Demo {\n# }\n$text='accolade } et apostrophe '' }'\nGet-PestoHelper\n}\n"
        self.assertEqual(guard.body(source, 'function Demo'), source[source.index('{'):].rstrip())
        self.assertEqual(guard.invoked_names(source), ['Get-PestoHelper'])

    def test_all_pesto_verbs_are_checked(self):
        self.assertEqual(guard.invoked_names("Resolve-PestoFoo; Copy-PestoBar # Get-PestoFalse\n"),
                         ['Copy-PestoBar', 'Resolve-PestoFoo'])

    def test_late_dot_source_is_rejected(self):
        dire = self.sources[guard.DIRE]
        source = '. ([scriptblock]::Create($identitySource))'
        dire = dire.replace(source, '', 1).replace(
            '    $domain =', '    ' + source + '\n    $domain =', 1)
        results = guard.checks(dire, self.sources[guard.AUTH], self.sources[guard.SAFE])
        self.assertTrue(any(c['status'] == 'FAIL' and 'dot-sources identitySource' in c['name'] for c in results))

    def test_authentication_mode_reaches_error_helper(self):
        worker = guard.body(self.sources[guard.DIRE], guard.WORKER)
        self.assertRegex(worker, re.compile(
            r'Add-PestoDomainIdentityCause\s+\$_\s+\$identiteAD\s+'
            r'-HasExplicitCredential:\(\$null -ne \$Request.Credential\)'))
        auth = self.sources[guard.AUTH]
        a, b = functions(auth)['Add-PestoDomainIdentityCause']
        helper = auth[a:b]
        self.assertIn('[switch]$HasExplicitCredential', helper)
        self.assertIn('if($HasExplicitCredential -or -not $Identity -or $null -eq $Identity.IsDomainUser){return $ErrorRecord}', helper)
        self.assertLess(helper.index('return $ErrorRecord'), helper.index('Get-PestoDomainIdentityWarning'))
        self.assertIn('$ErrorRecord.Exception', helper)
        self.assertIn('$detail, $inner)', helper)


if __name__ == '__main__':
    unittest.main()

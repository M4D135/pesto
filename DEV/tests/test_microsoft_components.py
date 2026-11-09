"""Read-only provenance inventory; no Microsoft binary is executed."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from microsoft_components import inventory, RSAT_FILES
from refresh_manifest import file_hash
from test_release_120 import fixture
import release_assurance


class MicrosoftComponentsTests(unittest.TestCase):
    def test_all_supplied_rsat_components_have_exact_hashes_and_unconfirmed_rights(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            entries = []
            for name in sorted(RSAT_FILES):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'non executable fixture')
                entries.append({'Path': name, 'SHA256': file_hash(path)})
            result = inventory(root, {'Files': entries})
            self.assertEqual(result['missingExpectedPaths'], [])
            self.assertEqual(len(result['components']), 6)
            for row in result['components']:
                self.assertEqual(row['sha256'], file_hash(root / row['path']))
                self.assertEqual(row['signature'], 'NOT_VERIFIED')
                self.assertEqual(row['originalPackage'], 'NOT_DOCUMENTED')
                self.assertEqual(row['redistributionRights'], 'NOT_ATTESTED')

    def test_changed_component_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            name = sorted(RSAT_FILES)[0]
            path = root / name
            path.parent.mkdir(parents=True)
            path.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                inventory(root, {'Files': [{'Path': name, 'SHA256': '0' * 64}]})

    def test_release_supplies_the_inventory_referenced_by_its_sbom(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            release_assurance.generate(fixture(root / 'source'), root / 'report')
            report = root / 'report'
            data = json.loads((report / 'microsoft-components.json').read_text())
            sums = json.loads((report / 'SHA256SUMS.json').read_text())
            self.assertEqual(data['status'], 'NO_MICROSOFT_COMPONENTS')
            self.assertEqual(sums['microsoft-components.json'], file_hash(report / 'microsoft-components.json'))


if __name__ == '__main__':
    unittest.main()

"""Offline provenance and pack contracts for the canonical shared libraries."""
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from refresh_manifest import runtime_files
from package_distribution import distribution_files


class SharedCommonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock = json.loads((ROOT / 'wad/common.lock.json').read_text())

    def test_embedded_dlls_match_the_pinned_bundle(self):
        self.assertEqual(self.lock['Version'], '0.2.0')
        self.assertIs(self.lock['SourceDirty'], False)
        self.assertEqual(self.lock['Consumer'], 'Pesto')
        self.assertEqual(self.lock['TargetFramework'], 'net472')
        self.assertRegex(self.lock['SourceCommit'], r'^[a-f0-9]{40}$')
        vendor_commit=(ROOT/'vendor/M4D.Admin.Common/source-commit.txt').read_text().strip()
        self.assertEqual(self.lock['SourceCommit'], vendor_commit)
        self.assertEqual({f['Name'] for f in self.lock['Files']},
                         {'M4D.Admin.Common.Core.dll', 'M4D.Admin.Common.Query.dll',
                          'M4D.Admin.Common.IO.dll', 'M4D.Admin.Common.Diagnostics.dll'} |
                         ({'M4D.Admin.Common.Wpf.dll'} if (ROOT/'wad/M4D.Admin.Common.Wpf.dll').exists() else set()))
        for file in self.lock['Files']:
            with self.subTest(file=file['Name']):
                data = (ROOT / 'wad' / file['Name']).read_bytes()
                self.assertEqual(len(data), file['Bytes'])
                self.assertEqual(hashlib.sha256(data).hexdigest(), file['SHA256'])

    def test_frozen_vendor_source_matches_canonical_digest(self):
        vendor = ROOT / 'vendor/M4D.Admin.Common'
        paths = sorted([*vendor.glob('src/**/*.cs'), vendor / 'version.json', vendor / 'tools/build.ps1'])
        canonical = '\n'.join(path.relative_to(vendor).as_posix() + '\0' +
                              hashlib.sha256(path.read_bytes()).hexdigest() for path in paths) + '\n'
        self.assertEqual(hashlib.sha256(canonical.encode()).hexdigest(), self.lock['SourceSHA256'])

    def test_both_channels_ship_lock_and_libraries_and_only_dev_ships_sources(self):
        required = {'wad/common.lock.json', 'wad/Pesto-Common.ps1',
                    'wad/M4D.Admin.Common.Core.dll', 'wad/M4D.Admin.Common.Query.dll',
                    'wad/M4D.Admin.Common.IO.dll', 'wad/M4D.Admin.Common.Diagnostics.dll'}
        self.assertTrue(required.issubset(runtime_files(ROOT)))
        for channel in ('DEV', 'PROD'):
            with self.subTest(channel=channel):
                files = distribution_files(ROOT, channel)
                self.assertTrue(required.issubset(files))
                self.assertFalse(any('M4D.Admin.Common.Tests.' in name for name in files))
                self.assertEqual(any(name.startswith('vendor/') for name in files), channel == 'DEV')


if __name__ == '__main__':
    unittest.main()

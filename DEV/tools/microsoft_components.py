"""Identify supplied RSAT files without inferring their origin or redistribution rights."""
from pathlib import Path
from refresh_manifest import safe_file, file_hash

RSAT_FILES = frozenset((
    'wad/Microsoft.ActiveDirectory.Management.dll',
    'wad/ActiveDirectoryPowerShellResources.dll',
    'wad/fr-FR/ActiveDirectoryPowerShellResources.dll.mui',
    'wad/ActiveDirectory.psd1',
    'wad/ActiveDirectory.Format.ps1xml',
    'wad/ActiveDirectory.Types.ps1xml',
))


def inventory(root, manifest):
    """Bind every listed component to verified bytes; never load the assemblies."""
    rows = []
    for entry in sorted(manifest['Files'], key=lambda entry: entry['Path']):
        if entry['Path'] not in RSAT_FILES:
            continue
        path = safe_file(Path(root), entry['Path'])
        digest = file_hash(path)
        if digest.lower() != entry['SHA256'].lower():
            raise ValueError('Microsoft component changed since manifest verification')
        rows.append({'path': entry['Path'], 'sha256': digest.lower(), 'bytes': path.stat().st_size,
                     'originalPackage': 'NOT_DOCUMENTED', 'signature': 'NOT_VERIFIED',
                     'redistributionRights': 'NOT_ATTESTED'})
    return {'schema': 1, 'components': rows,
            'missingExpectedPaths': sorted(RSAT_FILES - {row['path'] for row in rows}),
            'status': 'EVIDENCE_REQUIRED' if rows else 'NO_MICROSOFT_COMPONENTS',
            'requiredEvidence': ['Original Microsoft package and applicable terms',
                                 'Exact binary hashes and Windows signature inventory',
                                 'Documented redistribution authorization for the intended distribution'],
            'references': ['https://learn.microsoft.com/windows-server/remote/remote-server-administration-tools',
                           'https://www.microsoft.com/licensing/docs'],
            'limit': 'Installation documentation is not redistribution authorization. Hashes identify supplied bytes, not their original source. No assembly is executed.'}

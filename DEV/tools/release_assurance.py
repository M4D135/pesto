"""Offline release evidence, CycloneDX SBOM and in-toto/SLSA provenance.

No claim of a trusted publisher or Windows qualification is inferred from hashes.
All inputs are read only. The destination is new; local paths and environment values
are not exported. Python standard library only.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from refresh_manifest import verify_runtime, safe_file, file_hash, _is_link_or_junction
from microsoft_components import inventory as microsoft_inventory


def dump(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2).encode('utf-8') + b'\n'


def source_identity(root):
    result = subprocess.run(['git', '-C', str(root), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    commit = result.stdout.strip() if result.returncode == 0 else None
    if commit and not re.fullmatch('[0-9a-f]{40,64}', commit):
        raise ValueError('Invalid Git identity')
    dirty = None
    if commit:
        status = subprocess.run(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=normal'], capture_output=True, text=True, check=True)
        dirty = bool(status.stdout.strip())
    return {'commit': commit, 'dirty': dirty}


def sbom(root, manifest):
    components = []
    for entry in manifest['Files']:
        relative = entry['Path']
        components.append({'type': 'file', 'bom-ref': relative, 'name': relative,
                           'hashes': [{'alg': 'SHA-256', 'content': entry['SHA256'].lower()}]})
    return {'bomFormat': 'CycloneDX', 'specVersion': '1.6', 'version': 1,
            'metadata': {'component': {'type': 'application', 'bom-ref': 'pesto', 'name': 'Pesto', 'version': manifest['Version']},
                         'properties': [{'name': 'pesto:scope', 'value': 'closed runtime; configuration and local state excluded'},
                                        {'name': 'pesto:license-review', 'value': 'see microsoft-components.json; no license inferred from file presence'}]},
            'components': components,
            'dependencies': [{'ref': 'pesto', 'dependsOn': [e['Path'] for e in manifest['Files']]}]}


def evidence_envelope(report_path, scope, build_sha256, executed):
    if scope not in ('portable-doubles', 'windows-isolated', 'wpf-isolated', 'interactive-ui', 'live-ad', 'live-smb', 'live-replication'):
        raise ValueError('Unknown evidence scope')
    if not re.fullmatch('[0-9a-f]{64}', build_sha256):
        raise ValueError('Exact build SHA256 required')
    path = Path(report_path)
    if _is_link_or_junction(path) or not path.is_file():
        raise ValueError('A regular evidence file is required')
    return {'schema': 1, 'scope': scope, 'buildSHA256': build_sha256, 'executed': bool(executed),
            'report': {'name': path.name, 'sha256': file_hash(path), 'bytes': path.stat().st_size},
            'host': {'system': platform.system(), 'python': platform.python_version()},
            'resultInterpretation': 'Report bytes are preserved; this wrapper does not turn NOT_RUN/SKIP into PASS.'}


def generate(root, output, evidence=(), packs=()):
    root = Path(root).resolve(strict=True)
    output = Path(output).absolute()
    if output.exists() or output.is_symlink():
        raise FileExistsError('Choose a new evidence directory')
    output = output.resolve(strict=False)
    if output == root or root in output.parents:
        raise ValueError('Evidence output must be outside the source')
    manifest = verify_runtime(root)
    identity = source_identity(root)
    subject = [{'name': e['Path'], 'digest': {'sha256': e['SHA256'].lower()}} for e in manifest['Files']]
    record = root / 'tools/launcher/last-build.json'
    build = json.loads(record.read_text(encoding='utf-8-sig')) if record.is_file() else None
    if build and build.get('SHA256') != file_hash(root / 'Pesto.exe'):
        raise ValueError('Stale native build record')
    # Tool versions and input hashes are allowlisted; never dump the process environment.
    toolchain = {k: build[k] for k in ('Clang', 'Lld', 'Inputs', 'SHA256') if build and k in build}
    provenance = {'_type': 'https://in-toto.io/Statement/v1', 'subject': subject,
                  'predicateType': 'https://slsa.dev/provenance/v1', 'predicate': {
                      'buildDefinition': {'buildType': 'https://github.com/M4D135/pesto/build/inspection-v1',
                                          'externalParameters': {'version': manifest['Version'], 'source': identity, 'provenanceKind': 'inspection of supplied build and recorded compiler inputs'},
                                          'internalParameters': {'toolchain': toolchain},
                                          'resolvedDependencies': []},
                      'runDetails': {'builder': {'id': 'https://github.com/M4D135/pesto/DEV/tools/release_assurance.py'},
                                     'metadata': {'invocationId': hashlib.sha256(dump(subject)).hexdigest()},
                                     'byproducts': []}}}
    docs = {}
    for role in ('technicien', 'administrateur'):
        for suffix in ('pdf', 'docx'):
            rel = 'docs/Pesto-1.0-Guide-' + role + '.' + suffix
            path = root / rel
            if path.is_file():
                docs[rel] = file_hash(safe_file(root, rel))
    pack_records = []
    for path in packs:
        path = Path(path)
        if _is_link_or_junction(path) or not path.is_file() or path.suffix.lower() != '.zip':
            raise ValueError('Regular pack ZIP required')
        if path.name in {p['name'] for p in pack_records}:
            raise ValueError('Duplicate pack name')
        pack_records.append({'name': path.name, 'sha256': file_hash(path), 'bytes': path.stat().st_size})
    reports = []
    for path in evidence:
        path = Path(path)
        if _is_link_or_junction(path) or not path.is_file():
            raise ValueError('Invalid evidence attachment')
        reports.append({'name': path.name, 'sha256': file_hash(path), 'bytes': path.stat().st_size})
    contents = {'sbom.cdx.json': sbom(root, manifest), 'provenance.intoto.json': provenance,
                'microsoft-components.json': microsoft_inventory(root, manifest),
                'release.json': {'schema': 1, 'version': manifest['Version'], 'source': identity, 'provenanceKind': 'inspection of supplied build and recorded compiler inputs',
                                 'buildSHA256': file_hash(root / 'Pesto.exe'), 'guides': docs, 'evidence': reports, 'packs': pack_records,
                                 'signature': 'NOT_VERIFIED', 'attestation': 'UNSIGNED_STATEMENT',
                                 'qualifications': {'Windows': 'NOT_INFERRED', 'AD': 'NOT_INFERRED', 'WPF': 'NOT_INFERRED'},
                                 'toolchain': toolchain}}
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.pesto-evidence-', dir=output.parent) as temporary:
        stage = Path(temporary)
        for name, value in contents.items():
            (stage / name).write_bytes(dump(value))
        sums = {name: file_hash(stage / name) for name in contents}
        (stage / 'SHA256SUMS.json').write_bytes(dump(sums))
        output.mkdir()
        try:
            for path in stage.iterdir():
                shutil.copyfile(path, output / path.name)
        except BaseException:
            shutil.rmtree(output)
            raise
    return contents['release.json']


def compare_builds(first, second):
    a, b = verify_runtime(Path(first)), verify_runtime(Path(second))
    differences = [p for p in sorted({e['Path'] for e in a['Files']} | {e['Path'] for e in b['Files']})
                   if {e['Path']: e['SHA256'] for e in a['Files']}.get(p) != {e['Path']: e['SHA256'] for e in b['Files']}.get(p)]
    return {'schema': 1, 'identical': not differences, 'differentFiles': differences,
            'qualification': 'byte comparison of two supplied builds; no Windows execution inferred'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    create = sub.add_parser('create'); create.add_argument('--source', type=Path, required=True); create.add_argument('--output', type=Path, required=True); create.add_argument('--evidence', type=Path, action='append', default=[]); create.add_argument('--pack', type=Path, action='append', default=[])
    compare = sub.add_parser('compare'); compare.add_argument('first', type=Path); compare.add_argument('second', type=Path)
    args = parser.parse_args()
    result = generate(args.source, args.output, args.evidence, args.pack) if args.command == 'create' else compare_builds(args.first, args.second)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if args.command == 'compare' and not result['identical']: return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())

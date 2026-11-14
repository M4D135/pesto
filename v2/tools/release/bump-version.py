#!/usr/bin/env python3
"""Passe Pesto V2 à une nouvelle version et épingle le banc d'installation sur la release publiée courante.

Usage (depuis la racine du dépôt) : python3 v2/tools/release/bump-version.py 2.0.9 [--dry-run]

Modifie les trois déclarations de version (Directory.Build.props, app.manifest, pack-manifest.json) et les
épingles UI_UPDATE_FROM_* du workflow. Les épingles viennent de la release GitHub officielle de la version courante :
commit du tag et empreinte PROD de son SHA256SUMS. Rien n'est modifié si la release, le tag ou une empreinte
manque, ou si un fichier n'a pas exactement la forme attendue.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROPS = ROOT / 'v2/Directory.Build.props'
MANIFEST = ROOT / 'v2/src/Pesto.App/app.manifest'
PACK = ROOT / 'v2/tools/pack/pack-manifest.json'
WORKFLOW = ROOT / '.github/workflows/pesto-v2.yml'
VERSION = re.compile(r'^\d+\.\d+\.\d+$')


def fail(message):
    print(f'Refusé : {message} Aucun fichier modifié.', file=sys.stderr)
    sys.exit(1)


def run(*args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f'« {" ".join(args)} » a échoué : {result.stderr.strip()}')
    return result.stdout


def read(path):
    with path.open(encoding='utf-8', newline='') as handle:
        return handle.read()


def replace_once(text, pattern, replacement, label):
    updated, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count != 1:
        fail(f'{label} : {count} occurrence(s) au lieu d’une.')
    return updated


def published(version):
    tag = f'v{version}'
    refs = dict(reversed(line.split('\t')) for line in run('git', 'ls-remote', '--tags', 'origin', tag, tag + '^{}').splitlines())
    commit = refs.get(f'refs/tags/{tag}^{{}}') or refs.get(f'refs/tags/{tag}')
    if not commit or not re.fullmatch(r'[0-9a-f]{40}', commit):
        fail(f'tag {tag} introuvable sur origin.')
    sums = {}
    for line in run('gh', 'release', 'download', tag, '-p', 'SHA256SUMS', '-O', '-').splitlines():
        digest, _, name = line.partition('  ')
        sums[name.strip()] = digest.strip()
    digest = sums.get(f'Pesto_V2_PROD_{version}.zip', '')
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        fail(f'empreinte PROD absente du SHA256SUMS de {tag}.')
    return commit, digest


def main():
    args = [a for a in sys.argv[1:] if a != '--dry-run']
    dry = '--dry-run' in sys.argv[1:]
    if len(args) != 1 or not VERSION.match(args[0]):
        fail('indiquez une version X.Y.Z.')
    new = args[0]
    props = read(PROPS)
    match = re.search(r'<Version>(\d+\.\d+\.\d+)</Version>', props)
    if not match:
        fail('version courante illisible dans Directory.Build.props.')
    current = match.group(1)
    if tuple(map(int, new.split('.'))) <= tuple(map(int, current.split('.'))):
        fail(f'{new} n’est pas postérieure à la version courante {current}.')
    commit, digest = published(current)

    edits = {
        PROPS: replace_once(props, r'<Version>\d+\.\d+\.\d+</Version>', f'<Version>{new}</Version>', 'Directory.Build.props'),
        MANIFEST: replace_once(read(MANIFEST), r'(<assemblyIdentity version=")\d+\.\d+\.\d+\.0(")',
                               rf'\g<1>{new}.0\g<2>', 'app.manifest'),
        PACK: replace_once(read(PACK), r'^(  "version": ")\d+\.\d+\.\d+(",)(?=\r?$)', rf'\g<1>{new}\g<2>', 'pack-manifest.json'),
    }
    workflow = read(WORKFLOW)
    for key, value in (('VERSION', f"'{current}'"), ('COMMIT', commit), ('PROD_SHA256', digest)):
        workflow = replace_once(workflow, rf'^([ \t]+UI_UPDATE_FROM_{key}: )[^\r\n]*', rf'\g<1>{value}', f'UI_UPDATE_FROM_{key}')
    edits[WORKFLOW] = workflow

    print(f'{current} → {new} ; banc d’installation depuis v{current} ({commit[:7]}, PROD {digest[:8]}…).')
    for path, text in edits.items():
        changed = text != read(path)
        print(f'  {"modifié" if changed else "inchangé"} : {path.relative_to(ROOT)}')
        if changed and not dry:
            path.write_text(text, encoding='utf-8', newline='')
    if dry:
        print('Simulation : aucun fichier écrit.')


if __name__ == '__main__':
    main()

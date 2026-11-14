"""Lanceur des suites PowerShell de Pesto décrites par tests/suites.json (outil Mac/Linux, utilisable sous Windows).

Sous Windows, la recette reste TEST_TOUT.cmd -> tests/Run-AllTests.ps1 (aucune dépendance à Python sur la VM).
Ici : chaque chemin est résolu depuis la racine DEV (jamais depuis le dossier courant), les résultats vont dans
tests/results/<horodatage UTC>/summary.json (ignoré par Git). Une suite ignorée (SKIP) ne compte jamais comme
réussie : le code de sortie est non nul si une suite échoue ou si aucune suite n'a réussi.
"""
import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[1]
STATUSES = ('PASS', 'FAIL', 'SKIP')


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def get_build_hash(root):
    """Commit Git de la racine DEV, sinon 'inconnu' (jamais une date présentée comme un hash)."""
    try:
        result = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=str(root), capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except Exception:
        return 'inconnu'


def load_suites(suites_path):
    if not suites_path.is_file():
        raise SystemExit('ERREUR : fichier de suites introuvable : ' + str(suites_path))
    with open(suites_path, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise SystemExit('ERREUR : suites.json doit être une liste.')
    return data


def detect_platform():
    return 'Windows' if os.name == 'nt' else 'Portable'


def windows_powershell():
    system_root = os.environ.get('SystemRoot', r'C:\Windows')
    folder = 'Sysnative' if os.path.isdir(os.path.join(system_root, 'Sysnative')) else 'System32'
    return os.path.join(system_root, folder, 'WindowsPowerShell', 'v1.0', 'powershell.exe')


def portable_pwsh():
    return os.environ.get('PESTO_PWSH') or os.environ.get('PESTO_TEST_PWSH') or shutil.which('pwsh')


def list_missing(root, suites):
    configured = {s.get('file') for s in suites}
    present = {p.name for p in (root / 'tests').glob('Run-*.ps1') if p.suffix == '.ps1'}
    return sorted(present - configured - {'Run-AllTests.ps1'})


def run_suite(suite, root, platform, executable, timeout):
    """Retourne (statut, message) avec statut PASS, FAIL ou SKIP."""
    if suite.get('separate'):
        return 'SKIP', 'Lancée séparément : ' + str(suite['separate'])
    if platform != 'Windows' and suite.get('platform') != 'Portable':
        return 'SKIP', 'Plateforme ' + str(suite.get('platform')) + ' : Windows PowerShell 5.1 requis'
    suite_path = root / 'tests' / suite['file']
    if not suite_path.is_file():
        return 'FAIL', 'Fichier de test introuvable : ' + str(suite_path)
    if not executable:
        return 'FAIL', 'PowerShell introuvable : définir PESTO_PWSH'
    if platform == 'Windows':
        cmd = [executable, '-NoLogo', '-NoProfile', '-STA', '-ExecutionPolicy', 'RemoteSigned', '-File', str(suite_path)]
    else:
        cmd = [executable, '-NoLogo', '-NoProfile', '-File', str(suite_path)]
    try:
        result = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True, encoding='utf-8',
                                errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired:
        return 'FAIL', 'Délai dépassé (%d s)' % timeout
    except OSError as e:
        return 'FAIL', "Erreur d'exécution : " + str(e)
    if result.returncode == 0:
        return 'PASS', 'OK'
    tail = (result.stderr or result.stdout).strip()[-300:]
    return 'FAIL', 'Code retour %d : %s' % (result.returncode, tail)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=['Rapide', 'Complet'], default='Complet', help='Profil de tests')
    parser.add_argument('--list-missing', action='store_true', help='Liste les Run-*.ps1 absents de suites.json')
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT, help='Racine DEV (contient tests/suites.json)')
    parser.add_argument('--pwsh', help='PowerShell à utiliser (défaut : PESTO_PWSH, PATH ou powershell.exe sous Windows)')
    parser.add_argument('--platform', choices=['Windows', 'Portable'], default=detect_platform())
    parser.add_argument('--timeout', type=int, default=900, help='Délai par suite, en secondes')
    args = parser.parse_args(argv)

    root = args.root.resolve()
    suites = load_suites(root / 'tests' / 'suites.json')

    if args.list_missing:
        missing = list_missing(root, suites)
        if missing:
            print('Suites absentes de suites.json :')
            for name in missing:
                print('  - ' + name)
            return 1
        print('Aucune suite manquante.')
        return 0

    executable = args.pwsh or (windows_powershell() if args.platform == 'Windows' else portable_pwsh())
    stamp = utc_now().strftime('%Y%m%d_%H%M%S_%f')
    result_dir = root / 'tests' / 'results' / stamp
    result_dir.mkdir(parents=True, exist_ok=False)
    build_hash = get_build_hash(root)
    print('Suites PowerShell : plateforme %s, profil %s' % (args.platform, args.profile))
    print('Commit : ' + build_hash)
    print('-' * 40)

    results = []
    for suite in suites:
        if args.profile == 'Rapide' and suite.get('profile') != 'Rapide':
            status, message = 'SKIP', 'Profil Rapide'
        else:
            status, message = run_suite(suite, root, args.platform, executable, args.timeout)
        results.append({'name': suite.get('name'), 'file': suite.get('file'), 'status': status, 'message': message})
        print('[%s] %s : %s' % (status, suite.get('name'), message), flush=True)

    counts = {s: sum(1 for r in results if r['status'] == s) for s in STATUSES}
    summary = {'build_hash': build_hash, 'platform': args.platform, 'executable': executable, 'profile': args.profile,
               'timestamp': utc_now().isoformat(), 'counts': counts, 'results': results}
    summary_path = result_dir / 'summary.json'
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    print('\n%d réussies, %d en échec, %d ignorées (une suite ignorée ne compte jamais comme réussie).'
          % (counts['PASS'], counts['FAIL'], counts['SKIP']))
    print('Résultats : ' + str(summary_path))
    if counts['FAIL'] or not counts['PASS']:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Rejoue les brouillons du Spark une tâche à la fois, avec une barrière automatique, sur une branche neuve.

Pour chaque tâche « fait » du journal (dans l'ordre d'application d'origine), les blocs SEARCH/REPLACE et NEWFILE de sa
dernière réponse appliquée sont rejoués dans --repo (worktree propre). Barrière : syntaxe PowerShell des fichiers .ps1
touchés (vrai parseur, pwsh), XAML bien formé, suite Python complète sans nouvel échec par rapport à la référence, et
le test propre à la tâche s'il existe. Tâche gardée : un commit « Spark T0xx ». Tâche refusée : retour à l'état précédent,
raison notée dans replay.jsonl. Aucun jugement de fond : la relecture vient ensuite.

Usage : spark_replay.py --travail DOSSIER_SPARK --repo WORKTREE --taches taches.json [--pwsh PWSH]
"""
import argparse, json, re, subprocess, sys, xml.dom.minidom
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from spark_pesto import BLOCK, NEWF, load, save  # noqa: E402

PWSH_DEFAULT = str(Path.home() / 'Documents/Codex/2026-10-12/tu-x20/work/pesto-runtime/powershell-7.4.20/pwsh')
PARSE = r"""param([string[]]$Files) $bad=0; foreach($f in $Files){ $t=$null;$e=$null; [void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e); foreach($x in $e){ $bad++; "$($f):$($x.Extent.StartLineNumber) $($x.Message)" } }; "ERREURS=$bad" """


def sh(cmd, cwd, timeout=900):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


GENERATED = ['DEV/wad/Pesto.Engine.Runtime.ps1', 'DEV/wad/Pesto.Engine.psm1', 'DEV/wad/Pesto.Engine.psd1', 'DEV/wad/Pesto.Engine.build.json',
             'DEV/wad/Pesto.Engine.exports.json', 'DEV/wad/package.json', 'DEV/tools/launcher/pesto_runtime.h', 'DEV/tools/launcher/last-build.json',
             'DEV/Pesto.exe', 'DEV/tests/pesto-portable-validation.json', 'DEV/tests/login-compact-static-report.json', 'DEV/tests/rc23-native-portable.json']


def rebuild(repo, pwsh):
    """Module moteur, EXE et manifeste régénérés pour que les contrôles d'empreinte portent sur le brouillon."""
    env_path = '/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:' + __import__('os').environ.get('PATH', '')
    dev = Path(repo) / 'DEV'
    steps = [[pwsh, '-NoProfile', '-File', 'tools/Build-PestoEngineModule.ps1'],
             [sys.executable, 'tools/launcher/build_native.py'], [sys.executable, 'tools/refresh_manifest.py']]
    for cmd in steps:
        r = subprocess.run(cmd, cwd=dev, capture_output=True, text=True, timeout=600, env={**__import__('os').environ, 'PATH': env_path})
        if r.returncode:
            return False, ' '.join(Path(cmd[-1]).name for _ in [0]) + ' : ' + (r.stdout + r.stderr).strip().splitlines()[-1][:200]
    return True, ''


def restore_generated(repo):
    tracked = sh(['git', 'ls-files', '--'] + GENERATED, repo)[1].split()
    if tracked:
        sh(['git', 'checkout', '--'] + tracked, repo)


def python_failures(repo):
    rc, out = sh([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py'], Path(repo) / 'DEV', timeout=1200)
    bad = set(re.findall(r'^(?:FAIL|ERROR): (\S+ \([^)]+\))', out, re.M))
    ran = re.search(r'Ran (\d+) tests', out)
    return bad, int(ran.group(1)) if ran else 0


def apply_out(repo, out):
    """Rejoue une réponse ; rend (ok, fichiers, raison)."""
    staged, news = {}, []
    for path, old, new in BLOCK.findall(out):
        p = Path(repo) / path.strip()
        if not p.is_file():
            return False, [], f'fichier introuvable {path.strip()}'
        if p not in staged:
            staged[p] = list(load(p))
        t = staged[p][0]
        if t.count(old) != 1:
            o2 = old.strip('\n')
            if o2 and t.count(o2) == 1:
                old, new = o2, new.strip('\n')
            else:
                return False, [], f'bloc non applicable dans {path.strip()}'
        staged[p][0] = t.replace(old, new, 1)
    for path, content in NEWF.findall(out):
        p = Path(repo) / path.strip()
        if p.exists():
            return False, [], f'NEWFILE existe déjà {path.strip()}'
        news.append((p, content))
    for p, (t, bom, crlf) in staged.items():
        save(p, t, bom, crlf)
    for p, content in news:
        p.parent.mkdir(parents=True, exist_ok=True)
        ps1 = p.suffix in ('.ps1', '.psm1')
        save(p, content.replace('\r\n', '\n'), ps1, ps1)
    return True, [p for p in staged] + [p for p, _ in news], ''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--travail', required=True); ap.add_argument('--repo', required=True); ap.add_argument('--taches', required=True)
    ap.add_argument('--pwsh', default=PWSH_DEFAULT); ap.add_argument('--deja', default=''); ap.add_argument('--exclure', default='')
    a = ap.parse_args()
    work, repo = Path(a.travail), Path(a.repo)
    titles = {t['id']: t['titre'] for t in json.loads(Path(a.taches).read_text(encoding='utf-8'))}
    journal = [json.loads(l) for l in (work / 'journal.jsonl').read_text(encoding='utf-8').splitlines() if l.strip()]
    done = {l.split()[0] for l in Path(a.deja).read_text().splitlines()} if a.deja and Path(a.deja).exists() else set()
    excl = set(filter(None, a.exclure.split(',')))
    order = [(x['id'], x['tour']) for x in journal if x['res'] == 'fait' and x['id'] not in done and x['id'] not in excl]
    log = Path(a.repo).parent / ('replay-' + Path(a.repo).name + '.jsonl')
    parse_script = work / 'parse-fichiers.ps1'
    parse_script.write_text(PARSE.replace('param([string[]]$Files)', '$Files=$args;'), encoding='utf-8')
    rebuild(repo, a.pwsh)
    base_bad, base_ran = python_failures(repo)
    restore_generated(repo)
    print(f'référence : {base_ran} tests, {len(base_bad)} en échec ; {len(order)} tâches à rejouer', flush=True)
    for key, tour in order:
        out = (work / f'{key}-t{tour}.out.txt').read_text(encoding='utf-8', errors='replace')
        ok, files, why = apply_out(repo, out)
        verdict = 'gardé'
        if ok:
            ps = [str(f) for f in files if f.suffix in ('.ps1', '.psm1') and f.exists()]
            if ps:
                rc, txt = sh([a.pwsh, '-NoProfile', '-File', str(parse_script)] + ps, repo, timeout=300)
                m = re.search(r'ERREURS=(\d+)', txt)
                if not m or int(m.group(1)):
                    ok, why = False, 'syntaxe : ' + (txt.strip().splitlines()[0] if txt.strip() else 'parseur sans réponse')
            for f in files:
                if ok and f.suffix == '.xaml':
                    try:
                        xml.dom.minidom.parseString(f.read_bytes())
                    except Exception as e:
                        ok, why = False, f'XAML invalide : {e}'
            if ok:
                built, why_b = rebuild(repo, a.pwsh)
                if not built:
                    ok, why = False, 'reconstruction : ' + why_b
            if ok:
                bad, ran = python_failures(repo)
                new = sorted(bad - base_bad)
                if new:
                    ok, why = False, 'tests en échec : ' + '; '.join(new[:4])
        if ok:
            restore_generated(repo)
            sh(['git', 'add', '-A'], repo)
            rc, txt = sh(['git', 'commit', '-q', '-m', f'Spark {key} : {titles.get(key, "")[:90]}\n\nBrouillon du Spark rejoué derrière la barrière automatique (syntaxe, XAML, suite Python). Relecture humaine requise.'], repo)
        else:
            verdict = 'refusé'
            sh(['git', 'checkout', '--', '.'], repo); sh(['git', 'clean', '-fdq'], repo)
        with open(log, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'id': key, 'tour': tour, 'verdict': verdict, 'raison': why, 'fichiers': [str(Path(x).relative_to(repo)) for x in files] if ok or files else []}, ensure_ascii=False) + '\n')
        print(f'{key} {verdict} {why[:150]}', flush=True)
    print('fini', flush=True)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Petites tâches Pesto confiées au Spark, en parallèle (décision de David du 14/10 : « utilise à fond le spark »).

Entrée : un fichier JSON de tâches [{id, titre, spec, fichiers, tests}] (issu du plan de lots). Pour chaque tâche, le Spark
reçoit les règles de Pesto, la fiche et des extraits ciblés du code ; il rend des blocs SEARCH/REPLACE (et NEWFILE pour un
test) ou « STATUT: fait » si le code couvre déjà la demande. Les blocs sont appliqués dans le dossier --repo (un worktree de
travail, jamais le clone principal) ; un bloc qui ne s'applique pas repart au tour suivant avec les extraits relus.
Le résultat reste un brouillon : un agent Claude relit, teste et corrige avant intégration.

Usage : spark_pesto.py --taches taches.json --repo WORKTREE --travail DOSSIER [--jobs 6] [--tours 2] [--raisonner]
"""
import argparse, concurrent.futures as cf, json, os, re, subprocess, time
from pathlib import Path

KBZA = os.path.expanduser('~/bin/kbza')
BLOCK = re.compile(r'<<<<<<< SEARCH ([^\n]+)\n(.*?)\n=======\n(.*?)\n?>>>>>>> REPLACE', re.S)
NEWF = re.compile(r'<<<<<<< NEWFILE ([^\n]+)\n(.*?)\n?>>>>>>> END', re.S)
FUNC = re.compile(r'(?m)^\s*function\s+([A-Za-z][\w-]+)')

RULES = """Tu es un développeur senior Windows PowerShell 5.1 / WPF. Tu réalises UNE petite tâche dans Pesto (outil d'administration
Active Directory : jonction, renommage, déplacement de postes). Sources : DEV/wad/*.ps1 et DEV/wad/Pesto-Shell.xaml ; tests : DEV/tests.
Règles non négociables :
- Syntaxe Windows PowerShell 5.1 seulement : jamais ?:, ??, ??=, &&, ||, ?. ; C# compilé par Add-Type en C# 5.
- Ne jamais affaiblir une protection : un résultat incertain n'est jamais un succès ; aucune étape confirmée rejouée ; aucun
  redémarrage, retrait Entra ou changement de sécurité implicite ; aucun verrou effacé ; identifiants GP (%ProgramData%\\GP,
  mutex GP_*) jamais renommés ; contrôleur = celui découvert par Windows (pas de bascule PDC).
- Tout comportement nouveau sur le réseau réel est désactivé par défaut (option POLICY ou préférence) sauf demande contraire.
- Une fonction appelée dans un worker (runspace) doit figurer dans la liste de sources du worker ($script:PestoWorkerCoreNames
  dans Pesto-Core.ps1, ou la liste propre au worker). Pas de nouveau fichier .ps1 de runtime (il faudrait le manifeste).
- Contrôles WPF interactifs nouveaux : ToolTip + AutomationProperties.HelpText + ToolTipService.ShowOnDisabled="True" +
  AutomationProperties.AutomationId. Textes en français, accents corrects, apostrophes doublées '' dans les chaînes '...'.
- Ajoute un test : de préférence un fichier Python NEWFILE DEV/tests/test_spark_<id>.py (unittest, lit les sources en
  'utf-8-sig' et vérifie la présence/forme du code), sinon un cas dans un banc PowerShell portable existant.
FORMAT DE RÉPONSE, strict :
<<<<<<< SEARCH chemin/relatif/depuis/la/racine
texte EXACT copié des extraits (unique dans le fichier, quelques lignes suffisent)
=======
texte de remplacement
>>>>>>> REPLACE
(autant de blocs que nécessaire, 3 fichiers modifiés au plus sauf exception écrite dans la tâche)
<<<<<<< NEWFILE DEV/tests/test_spark_<id>.py
contenu
>>>>>>> END
STATUT: fait | report
NOTE: une ligne (ce qui a été fait, ou pourquoi reporter : il faudrait affaiblir une protection, plus de 3 fichiers, ou le
code à modifier n'est pas dans les extraits — dis alors lequel).
Si les extraits montrent que la demande est déjà couverte : aucun bloc, STATUT: fait, NOTE: « couvert par <fonction> (<fichier>) »."""


def load(p):
    b = p.read_bytes()
    bom = b.startswith(b'\xef\xbb\xbf')
    t = b.decode('utf-8-sig', errors='replace')
    crlf = '\r\n' in t
    return t.replace('\r\n', '\n'), bom, crlf


def save(p, t, bom, crlf):
    if crlf:
        t = t.replace('\n', '\r\n')
    p.write_bytes((b'\xef\xbb\xbf' if bom else b'') + t.encode('utf-8'))


def excerpts(repo, task, budget=40000, per_file=14000, ctx=30):
    """Fichiers de la tâche : entiers s'ils sont courts, sinon fenêtres autour des fonctions et mots de la fiche."""
    text = (task.get('spec', '') + ' ' + task.get('titre', '') + ' ' + task.get('tests', ''))
    names = set(re.findall(r'\b[A-Z][a-z]+-Pesto[\w]+|\bPesto[A-Z][\w]+|\b[A-Z][a-z]+-[A-Z][\w]+', text))
    words = {w.lower() for w in re.findall(r'[A-Za-zÀ-ÿ]{7,}', text)}
    out, total = [], 0
    for rel in task.get('fichiers', []):
        p = Path(repo) / rel
        if not p.is_file():
            continue
        t, _, _ = load(p)
        lines = t.split('\n')
        if len(t) <= per_file:
            chunk = f'=== {rel} (fichier entier, {len(lines)} lignes)\n{t}'
        else:
            hits = []
            for k, l in enumerate(lines):
                m = FUNC.match(l)
                if m and m.group(1) in names:
                    hits.append(k)
                elif any(n in l for n in names) or sum(1 for w in words if w in l.lower()) >= 2:
                    hits.append(k)
            wins = []
            for k in hits[:60]:
                a, b = max(0, k - ctx), min(len(lines), k + ctx)
                if wins and a <= wins[-1][1]:
                    wins[-1][1] = max(wins[-1][1], b)
                else:
                    wins.append([a, b])
            parts, size = [], 0
            for a, b in wins:
                s = '\n'.join(lines[a:b])
                if size + len(s) > per_file:
                    break
                parts.append(f'--- lignes {a + 1}-{b}\n{s}'); size += len(s)
            chunk = f'=== {rel} (extraits)\n' + '\n'.join(parts) if parts else f'=== {rel} : aucun extrait pertinent trouvé'
        if total + len(chunk) > budget:
            break
        out.append(chunk); total += len(chunk)
    return '\n\n'.join(out)


def apply(repo, out):
    blocks = BLOCK.findall(out); news = NEWF.findall(out)
    st = re.search(r'STATUT:\s*(\w+)', out); note = re.search(r'NOTE:\s*(.+)', out)
    statut = st.group(1).lower() if st else '?'; note = note.group(1).strip() if note else ''
    if statut.startswith('report'):
        return 'reporte', note
    if not blocks and not news:
        return ('couvert' if statut.startswith('fait') else 'vide'), note or 'aucun bloc rendu'
    staged = {}
    for path, old, new in blocks:
        p = Path(repo) / path.strip()
        if not p.is_file():
            return 'echec', f'fichier introuvable : {path.strip()}'
        if p not in staged:
            staged[p] = list(load(p))
        t = staged[p][0]
        n = t.count(old)
        if n != 1:
            o2 = old.strip('\n')
            if o2 and t.count(o2) == 1:
                old = o2; new = new.strip('\n')
            else:
                return 'echec', f'bloc introuvable ou ambigu ({n}) dans {path.strip()} : {old[:80]!r}'
        staged[p][0] = t.replace(old, new, 1)
    for path, content in news:
        p = Path(repo) / path.strip()
        if p.exists():
            return 'echec', f'NEWFILE existe déjà : {path.strip()}'
    for p, (t, bom, crlf) in staged.items():
        save(p, t, bom, crlf)
    for path, content in news:
        p = Path(repo) / path.strip()
        p.parent.mkdir(parents=True, exist_ok=True)
        ps1 = p.suffix in ('.ps1', '.psm1')
        save(p, content.replace('\r\n', '\n'), ps1, ps1)
    files = sorted({str(p.relative_to(repo)) for p in staged} | {path.strip() for path, _ in news})
    return 'fait', (note + ' [' + ', '.join(files) + ']').strip()


def run(repo, work, task, tour, extra, mode):
    key = task['id']
    prompt = (RULES + f"\n\nTÂCHE {key} : {task['titre']}\nSPÉCIFICATION :\n{task['spec']}\nTEST ATTENDU : {task.get('tests', '')}\n"
              + extra + '\n\nEXTRAITS DU CODE ACTUEL :\n\n' + excerpts(repo, task))
    pf = work / f'{key}-t{tour}.prompt.txt'; of = work / f'{key}-t{tour}.out.txt'; ef = work / f'{key}-t{tour}.err.txt'
    pf.write_text(prompt, encoding='utf-8')
    t0 = time.time()
    with open(of, 'w', encoding='utf-8') as o, open(ef, 'w', encoding='utf-8') as e:
        rc = subprocess.call([KBZA, 'ask', '--prompt-file', str(pf), '--max-tokens', '0', '--no-memory', '--reasoning-mode', mode], stdout=o, stderr=e)
    return key, rc, of.read_text(encoding='utf-8', errors='replace'), int(time.time() - t0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--taches', required=True); ap.add_argument('--repo', required=True); ap.add_argument('--travail', required=True)
    ap.add_argument('--jobs', type=int, default=6); ap.add_argument('--tours', type=int, default=2); ap.add_argument('--raisonner', action='store_true')
    a = ap.parse_args()
    work = Path(a.travail); work.mkdir(parents=True, exist_ok=True)
    tasks = json.loads(Path(a.taches).read_text(encoding='utf-8'))
    mode = 'inherit' if a.raisonner else 'direct'
    log = work / 'journal.jsonl'
    pending = {t['id']: (t, '') for t in tasks}
    print(f'{len(pending)} tâches, {a.jobs} en parallèle, mode {mode}', flush=True)
    for tour in range(1, a.tours + 1):
        if not pending:
            break
        nxt = {}
        with cf.ThreadPoolExecutor(a.jobs) as pool:
            futs = [pool.submit(run, a.repo, work, t, tour, extra, mode) for t, extra in pending.values()]
            for fu in cf.as_completed(futs):
                key, rc, out, secs = fu.result()
                res, note = ('erreur', f'kbza rc={rc}') if rc != 0 else apply(a.repo, out)
                with open(log, 'a', encoding='utf-8') as f:
                    f.write(json.dumps({'t': time.strftime('%H:%M:%S'), 'id': key, 'tour': tour, 'res': res, 'note': note, 's': secs}, ensure_ascii=False) + '\n')
                print(f'{time.strftime("%H:%M:%S")} {key} {res} ({secs}s) : {note[:160]}', flush=True)
                if res in ('echec', 'vide', 'erreur'):
                    nxt[key] = (pending[key][0], f'\nATTENTION : réponse précédente non appliquée ({note}). Copie les SEARCH exactement depuis les extraits.')
        pending = nxt
    print('fini', flush=True)


if __name__ == '__main__':
    main()

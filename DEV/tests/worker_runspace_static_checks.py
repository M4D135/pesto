#!/usr/bin/env python3
# Garde du contrat d'execution des workers asynchrones de Pesto.
#
# Start-PestoAsyncOperation cree un runspace neuf (RunspaceFactory::CreateRunspace) et ne lui
# transfere que le TEXTE du scriptblock plus ses arguments : aucune fonction du moteur n'y existe.
# Un worker ne peut donc appeler une fonction du moteur que si la source qu'il dot-source la lui
# fournit. Le commit 44feb34 a ajoute deux appels de ce type dans le worker de snapshot AD sans
# fournir les definitions : l'ecran de connexion rendait « Acces AD non etabli / Le terme
# « Get-PestoWindowsAuthIdentity » n'est pas reconnu », une panne inventee a la place du vrai
# refus du controleur. Mesure sur PowerShell 5.1.26100.6584 : dans la session neuve alimentee par
# Get-PestoADLoaderSource seule, les deux fonctions etaient ABSENTES.
#
# Ce controle est statique : il ne lance ni PowerShell ni Pesto.
import argparse, json, re, sys
from pathlib import Path
from ps_lexical import functions, tokens

DIRE = 'Pesto-Directory.ps1'
AUTH = 'Pesto-Authentication.ps1'
SAFE = 'Pesto-Safety.ps1'
WORKER = '$script:PestoDirectorySnapshotWorker = {'
FACTORY = 'function New-PestoDirectorySnapshotRequest'
EXPORTER = 'function Get-PestoDirectoryIdentitySource'
PROJECTION = 'function Get-PestoDirectoryProjectionSource'
LOADER = 'function Get-PestoADLoaderSource'
# Noms d'applet de commande que le worker est autorise a appeler sans qu'on les lui fournisse :
# cmdlets du module Active Directory et primitives du moteur, jamais des fonctions Pesto.
CALL = re.compile(r"[A-Za-z][A-Za-z0-9]*-Pesto[A-Za-z][A-Za-z0-9]*", re.I)
LIST = re.compile(r"foreach\s*\(\s*\$name\s+in\s+@\(([^)]*)\)\s*\)", re.I)


def body(text, opener):
    """Le bloc { ... } equilibre qui suit `opener`, decoupe par appariement des accolades."""
    i = text.index(opener)
    # Ignorer accolades dans les commentaires et chaînes, y compris les apostrophes doublées.
    tt = tokens(text[i:])
    b = None
    depth = 0
    for kind, a, z in tt:
        if kind == '{':
            if b is None:
                b = i + a
            depth += 1
        elif kind == '}' and b is not None:
            depth -= 1
            if depth == 0:
                return text[b:i + z]
    raise ValueError('accolades non equilibrees apres ' + opener)


def supplied_names(text, opener, label):
    """Les noms que la fonction X envoie reellement dans le runspace du worker."""
    try:
        m = LIST.search(body(text, opener))
    except (ValueError, StopIteration):
        return []
    if not m:
        return []
    return [x.strip().strip("'\"") for x in m.group(1).split(',') if x.strip()]


def invoked_names(worker_text):
    """Toute reference a une fonction Pesto dans le texte du worker, hors litteraux."""
    return sorted({worker_text[a:b] for kind, a, b in tokens(worker_text)
                   if kind == 'word' and CALL.fullmatch(worker_text[a:b])})


def checks(dire, auth, safe):
    r = []
    add = lambda **k: r.append(k)
    try:
        worker = body(dire, WORKER)
    except ValueError:
        return [{'name': 'worker body', 'status': 'FAIL', 'detail': 'accolades non equilibrees'}]
    try:
        factory = body(dire, FACTORY)
    except ValueError:
        factory = ''
    loader = supplied_names(safe, LOADER, 'loader')
    ident = supplied_names(auth, EXPORTER, 'identity')
    projection = supplied_names(dire, PROJECTION, 'projection')
    given = set(loader) | set(ident) | set(projection)
    # Les helpers exportés ont eux aussi besoin de leurs dépendances dans le runspace neuf.
    definitions = {}
    for source in (dire, auth, safe):
        for name, (a, b) in functions(source).items():
            definitions[name.casefold()] = source[a:b]
    called = invoked_names(worker)
    required = set(called)
    for name in given:
        required.update(invoked_names(definitions.get(name.casefold(), '')))
    given_folded = {name.casefold() for name in given}
    missing = sorted(name for name in required if name.casefold() not in given_folded)

    add(name='Worker body extracted and balanced', status='PASS' if worker else 'FAIL', functions=len(called))
    add(name='AD resolver source still declared', status='PASS' if loader else 'FAIL', names=loader)
    add(name='Identity source exporter declared', status='PASS' if ident else 'FAIL', names=ident)
    add(name='Projection source exporter declared', status='PASS' if projection else 'FAIL', names=projection)
    # Le coeur de la garde : ce que le worker appelle doit voyager jusqu'a son runspace.
    add(name='Every Pesto function the worker calls is shipped into its runspace',
        status='PASS' if not missing else 'FAIL',
        detail='absentes du runspace : ' + ', '.join(missing) if missing else '',
        called=called, required=sorted(required), shipped=sorted(given))
    # Le worker doit exiger la source, pas l'accepter silencieusement absente.
    add(name='Worker refuses to run without the identity source',
        status='PASS' if 'IdentitySource' in worker and re.search(r"throw 'Résolveur d''identité", worker) else 'FAIL')
    add(name='Request factory ships the identity source',
        status='PASS' if re.search(r"IdentitySource=\(Get-PestoDirectoryIdentitySource\)", factory) else 'FAIL')
    add(name='Request factory ships the projection source',
        status='PASS' if re.search(r"ProjectionSource=\(Get-PestoDirectoryProjectionSource\)", factory) else 'FAIL')
    add(name='Worker refuses to run without the projection source',
        status='PASS' if re.search(r"if\(-not \$projectionSource\)\{throw", worker) else 'FAIL')
    words = [(worker[a:b].casefold(), a, b) for kind, a, b in tokens(worker) if kind == 'word']
    first_call = next((a for word, a, b in words if CALL.fullmatch(word)), len(worker))
    for variable in ('identitySource', 'adLoader', 'projectionSource'):
        candidates = re.finditer(r'(?mi)^[ \t]*\.\s*\(\[scriptblock\]::Create\(\$' + variable + r'\)\)', worker)
        # Une ligne de dot-source commentée ou stockée dans une chaîne ne charge rien.
        loaded = next((m for m in candidates if [word for word, a, b in words if m.start() <= a < m.end()]
                       == ['scriptblock', 'create', variable.casefold()]), None)
        add(name='Worker dot-sources ' + variable + ' before calling Pesto helpers',
            status='PASS' if loaded and loaded.start() < first_call else 'FAIL')
    # Une liste qui nomme une fonction supprimee ne se voit qu'a l'execution par Get-Command :
    # elle est verifiee ici contre les definitions reellement presentes a profondeur 0.
    ghost = sorted(x for x in given if x.casefold() not in definitions)
    add(name='Shipped names are really defined at depth 0',
        status='PASS' if not ghost else 'FAIL', detail='noms sans definition : ' + ', '.join(ghost) if ghost else '')
    return r


# Chaque mutant nomme le fichier qu'il doit changer ; un mutant qui ne s'applique pas compte comme
# non detecte, jamais comme un succes. Les motifs sont independants du style de fin de ligne :
# le depot melange CRLF et LF selon les fichiers.
MUTATIONS = (
    ('Omettre le parseur DN transitif de la projection', DIRE,
     lambda s: s.replace("'Split-PestoDistinguishedName','Test-PestoDNWithinScope'", "'Test-PestoDNWithinScope'", 1)),
    ('Ne plus fournir la projection dans la requete', DIRE,
     lambda s: re.sub(r'[ \t]*ProjectionSource=\(Get-PestoDirectoryProjectionSource\)\r?\n', '', s, count=1)),
    ('Ne plus charger la projection dans le worker', DIRE,
     lambda s: s.replace('. ([scriptblock]::Create($projectionSource))', '# source non chargee', 1)),
    ('Retirer Get-PestoWindowsAuthIdentity de la source d identite', AUTH,
     lambda s: s.replace("'Get-PestoWindowsAuthIdentity','Get-PestoDomainIdentityWarning'", "'Get-PestoDomainIdentityWarning'")),
    ('Ne plus fournir la source d identite dans la requete', DIRE,
     lambda s: re.sub(r'[ \t]*IdentitySource=\(Get-PestoDirectoryIdentitySource\)\r?\n', '', s, count=1)),
    ('Retirer l exigence de la source dans le worker', DIRE,
     lambda s: re.sub(r"[ \t]*if\(-not \$identitySource\)\{throw 'Résolveur d''identité absent du worker\.'\}\r?\n"
                      r'[ \t]*\. \(\[scriptblock\]::Create\(\$identitySource\)\)\r?\n', '', s, count=1)),
    ('Ne plus charger la source d identite dans le worker', DIRE,
     lambda s: s.replace('. ([scriptblock]::Create($identitySource))', '# source non chargee', 1)),
    ('Ne plus charger le resolveur AD dans le worker', DIRE,
     lambda s: s.replace('. ([scriptblock]::Create($adLoader))', '# source non chargee', 1)),
    ('Omettre une dependance transitive du resolveur AD', SAFE,
     lambda s: s.replace("'Assert-PestoPlainPath','Import-PestoADModule'", "'Import-PestoADModule'", 1)),
    ('Commenter le chargement de la source d identite', DIRE,
     lambda s: s.replace('. ([scriptblock]::Create($identitySource))', '<#\n. ([scriptblock]::Create($identitySource))\n#>', 1)),
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument('--wad', type=Path, help='default: <root>/wad')
    ap.add_argument('--report', type=Path)
    a = ap.parse_args()
    root = a.root.resolve()
    wad = a.wad or root / 'wad'
    dire = (wad / DIRE).read_bytes().decode('utf-8-sig')
    auth = (wad / AUTH).read_bytes().decode('utf-8-sig')
    safe = (wad / SAFE).read_bytes().decode('utf-8-sig')
    r = checks(dire, auth, safe)
    negative = []
    for name, fname, mutate in MUTATIONS:
        pair = {DIRE: dire, AUTH: auth, SAFE: safe}
        mutated = dict(pair)
        mutated[fname] = mutate(pair[fname])
        applied = mutated[fname] != pair[fname]
        bad = [x['name'] for x in checks(mutated[DIRE], mutated[AUTH], mutated[SAFE]) if x['status'] == 'FAIL'] if applied else []
        negative.append({'name': name, 'file': fname, 'applied': applied, 'detected': bool(bad), 'failed_checks': bad})
    failed = sum(x['status'] == 'FAIL' for x in r)
    report = {'utc': str(__import__('datetime').datetime.now(__import__('datetime').timezone.utc)),
              'scope': 'Static check of the async worker runspace contract. No PowerShell execution.',
              'summary': {'checks': len(r), 'passed': len(r) - failed, 'failed': failed},
              'checks': r, 'negative_controls': negative}
    out = a.report or root / 'tests/worker-runspace-report.json'
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for c in r:
        print(c['status'], c['name'] + ('' if c['status'] == 'PASS' else ' : ' + c.get('detail', '')))
    for n in negative:
        if not n['detected']:
            print('NEGATIVE MISSED', n['name'], 'sur', n['file'], '(mutation appliquee: ' + str(n['applied']) + ')')
    print(json.dumps(report['summary']), '; injected defects detected:',
          sum(x['detected'] for x in negative), '/', len(negative))
    return 1 if failed or not all(x['detected'] for x in negative) else 0


if __name__ == '__main__':
    raise SystemExit(main())

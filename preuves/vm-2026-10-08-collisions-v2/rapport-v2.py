"""Rapport HTML du banc de collisions v2 (08/10/2026) : synthèse, arbitre AD, détail de chaque tour et de chaque technicien.
Entrées : collisions-v2.json et collisions-v2.txt (copiés depuis la VM). Sortie : collisions-v2.html (autonome)."""
from collections import defaultdict, OrderedDict
from html import escape
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
rows = json.loads((HERE / 'collisions-v2.json').read_text('utf-8-sig'))
txt = (HERE / 'collisions-v2.txt').read_text('utf-8-sig').splitlines()

modes = list(OrderedDict.fromkeys(r['Mode'] for r in rows))
profiles = list(OrderedDict.fromkeys(r['Profile'] for r in rows))
by = defaultdict(list)
for r in rows:
    by[(r['Profile'], r['Mode'])].append(r)


def stats(rs):
    techs = [t for r in rs for t in r['Techs']]
    done = [t for t in techs if t.get('Final')]
    return {
        'rounds': len(rs),
        'dup_click': sum(1 for r in rs if r['DupClick']),
        'switch': sum(r['AutoSwitch'] for r in rs),
        'fail': sum(r['FailAfter'] for r in rs),
        'reconfirm': sum(1 for t in techs if (t.get('Confirmations') or 0) > 1),
        'techs': len(techs),
        'maxconf': max((t.get('Confirmations') or 0) for t in techs),
        'dup': sum(r['DupFinal'] for r in rs),
        'orph': sum(r['Orphans'] for r in rs),
        'err': sum(r['Errors'] for r in rs),
        'mean': sum(t['Ms'] for t in done) / len(done) / 1000 if done else 0,
        'max': max((t['Ms'] for t in done), default=0) / 1000,
    }


def num(n):
    return n[-3:] if n else '—'


def chain(t):
    """Parcours d'un technicien : noms successifs, avec la raison de chaque changement."""
    parts = []
    for e in t.get('Events') or []:
        k, n = e['K'], num(e.get('N', ''))
        if k == 'affiché':
            parts.append(f'<span class="n">{n}</span>')
        elif k in ('autre nom affiché', 'nom suivant'):
            parts.append(f'<span class="arrow">→</span><span class="n">{n}</span>')
        elif k == 'détenu ailleurs':
            parts.append('<span class="tag held" title="Réservé par un autre poste avant le clic">registre</span>')
        elif k == 'clic':
            parts.append('<span class="tag click" title="Clic sur Vérifier puis joindre">clic</span>')
        elif k == 'détenu ailleurs (traitement)':
            parts.append('<span class="tag held" title="Le registre répond : réservé par un autre poste">détenu</span>')
        elif k == 'détenu au registre : nom suivant':
            parts.append('<span class="tag sw" title="Nom suivant avant la confirmation (registre)">bascule</span>')
        elif k in ('pris au contrôle', 'pris à la réservation AD'):
            parts.append(f'<span class="tag sw" title="{escape(k)}">{"AD" if "AD" in k else "pris"}</span>')
        elif k == 'confirmation':
            parts.append('<span class="tag conf" title="Le technicien lit et confirme">confirmé</span>')
        elif k == 'échec après confirmation':
            parts.append(f'<span class="tag fail" title="{escape(e.get("D", ""))}">refusé</span>')
        elif k in ('ajouté', 'ajouté (compte réservé)'):
            parts.append(f'<span class="tag ok">ajouté {n}</span>')
        elif k == 'erreur':
            parts.append(f'<span class="tag fail">erreur : {escape(e.get("D", ""))}</span>')
    return ' '.join(parts)


css = """
:root{--bg:#f7f7f5;--card:#fff;--fg:#1d1d1b;--muted:#6b6b66;--line:#e2e1dc;--ok:#1f7a45;--okbg:#e3f3e8;--bad:#b42318;--badbg:#fde7e4;
--warn:#8a5a00;--warnbg:#fdf1d8;--info:#2c5cc5;--infobg:#e6edfb;--chip:#efeee9}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#151514;--card:#1f1f1d;--fg:#ecebe6;--muted:#a3a29b;--line:#34332f;
--ok:#5fcf8c;--okbg:#17321f;--bad:#ff8a7a;--badbg:#3a1c18;--warn:#f0c35c;--warnbg:#3a2f14;--info:#8fb0ff;--infobg:#1b2742;--chip:#2a2a27}}
:root[data-theme="dark"]{--bg:#151514;--card:#1f1f1d;--fg:#ecebe6;--muted:#a3a29b;--line:#34332f;--ok:#5fcf8c;--okbg:#17321f;--bad:#ff8a7a;
--badbg:#3a1c18;--warn:#f0c35c;--warnbg:#3a2f14;--info:#8fb0ff;--infobg:#1b2742;--chip:#2a2a27}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}h1{font-size:24px;margin:0 0 4px}h2{font-size:18px;margin:32px 0 8px}
h3{font-size:15px;margin:20px 0 6px}p{margin:6px 0}.muted{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:12px 0}
.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13.5px}th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{font-weight:600;color:var(--muted);white-space:nowrap}td.c{text-align:center}.good{background:var(--okbg);color:var(--ok);font-weight:600}
.badc{background:var(--badbg);color:var(--bad);font-weight:600}.n{font-family:ui-monospace,Menlo,monospace;font-weight:600}
.arrow{color:var(--muted);margin:0 2px}.tag{display:inline-block;font-size:11.5px;padding:0 6px;border-radius:9px;background:var(--chip);color:var(--muted);margin:1px 0}
.tag.ok{background:var(--okbg);color:var(--ok)}.tag.fail{background:var(--badbg);color:var(--bad)}.tag.sw,.tag.held{background:var(--warnbg);color:var(--warn)}
.tag.conf,.tag.click{background:var(--infobg);color:var(--info)}details{margin:6px 0}summary{cursor:pointer;font-weight:600}
.bar{display:inline-block;vertical-align:middle;height:8px;border-radius:4px;background:var(--bad);margin-right:6px}.barz{color:var(--ok);font-weight:600}.kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px}
.kpi div{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px}.kpi b{display:block;font-size:22px}
"""

out = ['<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
       '<title>Collisions de noms Pesto</title>', f'<style>{css}</style></head><body><main>']
out.append('<h1>Collisions de noms : banc v2 sur l\'AD réel</h1>')
out.append('<p class="muted">PESTO-W11-TEST, 8 octobre 2026. 4 techniciens (processus séparés), même site, même service, même type ; '
           'vrai code de Pesto, vrai contrôleur DC01 ; 6 tours par réglage et par profil. Chaque compte créé est supprimé à la fin du tour.</p>')

tot = stats(rows)
out.append('<div class="kpi">'
           f'<div><b>{len(rows)}</b>tours, {tot["techs"]} ajouts au domaine</div>'
           f'<div><b>{tot["dup"]}</b>nom en double dans l\'AD</div>'
           f'<div><b>{tot["orph"]}</b>compte orphelin</div>'
           f'<div><b>{tot["err"]}</b>erreur de technicien</div></div>')

out.append('<h2>Ce qui gêne le technicien : refus après sa confirmation</h2>')
out.append('<p>Un refus après confirmation oblige le technicien à reconfirmer un autre nom. Une bascule avant confirmation est transparente : '
           'Pesto propose et revérifie le nom suivant avant d\'afficher le récapitulatif.</p>')
for prof in profiles:
    desc = 'tous au même instant' if prof == 'Simultané' else 'départs étalés sur 6 s'
    out.append(f'<h3>{escape(prof)} ({desc})</h3><div class="card scroll"><table><tr><th>Réglage</th><th>Refus après confirmation</th>'
               '<th class="c">Techniciens ayant reconfirmé</th><th class="c">Bascules avant confirmation</th><th class="c">Même nom au clic</th>'
               '<th class="c">Durée moyenne</th></tr>')
    mx = max(stats(by[(prof, m)])['fail'] for m in modes) or 1
    for m in modes:
        s = stats(by[(prof, m)])
        bar = (f'<div class="bar" style="width:{max(4, int(160 * s["fail"] / mx))}px"></div> {s["fail"]}' if s['fail'] else '<span class="barz">0</span>')
        cls = 'good' if s['reconfirm'] == 0 else 'badc'
        out.append(f'<tr><td>{escape(m)}</td><td>{bar}</td><td class="c {cls}">{s["reconfirm"]} / {s["techs"]} (jusqu\'à {s["maxconf"]} fois)</td>'
                   f'<td class="c">{s["switch"]}</td><td class="c">{s["dup_click"]} / {s["rounds"]} tours</td><td class="c">{s["mean"]:.1f} s</td></tr>')
    out.append('</table></div>')

out.append('<h2>L\'arbitre final : l\'AD</h2><div class="card">')
for line in txt:
    if line.startswith('essai ') or line.startswith('conflit entre OU'):
        out.append(f'<p class="n" style="font-weight:400">{escape(line)}</p>')
out.append('<p class="muted">Quatre processus réservent le même nom à la même milliseconde avec le worker de réservation de Pesto : '
           'un seul compte est créé, les trois autres reçoivent « Taken » et passent au nom suivant. Un nom existant dans une autre OU est aussi refusé.</p></div>')

out.append('<h2>Détail de chaque tour</h2><p class="muted">Pour chaque technicien : noms successifs et événements '
           '(registre = nom réservé par un autre poste avant le clic ; détenu = réponse du registre pendant la vérification ; bascule / pris / AD = nom suivant avant la confirmation ; '
           'refusé = échec après confirmation). Survolez une étiquette pour le détail.</p>')
for prof in profiles:
    out.append(f'<h3>{escape(prof)}</h3>')
    for m in modes:
        rs = by[(prof, m)]
        s = stats(rs)
        flag = 'aucun refus après confirmation' if s['fail'] == 0 else f'{s["fail"]} refus après confirmation'
        out.append(f'<details><summary>{escape(m)} : {flag}</summary><div class="card scroll"><table><tr><th>Tour</th><th>Série</th>'
                   + ''.join(f'<th>Technicien {i}</th>' for i in range(1, 5)) + '</tr>')
        for r in rs:
            cells = ''.join(f'<td>{chain(t)}<br><span class="muted">départ +{t.get("StartMs", 0)} ms, clic {t.get("ClickMs", 0)} ms, '
                            f'{t.get("Ms", 0) / 1000:.1f} s</span></td>' for t in sorted(r['Techs'], key=lambda x: x.get('Tech', 0)))
            out.append(f'<tr><td class="c">{r["Round"]}</td><td class="n">{escape(r["Series"])}</td>{cells}</tr>')
        out.append('</table></div></details>')

out.append('<h2>Méthode et limites</h2><div class="card">'
           '<p><b>Vrai code de Pesto</b> (extrait des fichiers livrés, empreintes dans collisions-v2.txt) : liste des noms libres, tirage au hasard, '
           'worker du registre partagé, verrou d\'opération, worker de réservation AD. Chaque appel AD ou registre passe par un runspace neuf, comme dans Pesto.</p>'
           '<p><b>Reproduit sans fenêtre</b> : sélection du nom, minuterie d\'une seconde du registre (réservation après 900 ms de stabilité), '
           'enchaînement vérification → réservation AD → confirmation (lecture de 1,5 à 4 s) → exécution. La jonction elle-même est remplacée par la création '
           'du compte ordinateur dans l\'OU, précédée des relectures AD et du verrou, comme dans le worker de jonction.</p>'
           '<p><b>« Registre (avant correctif) »</b> reproduit l\'ancien comportement : aucune réservation pendant la vérification ni bascule sur réponse du registre.</p>'
           '<p><b>Limites</b> : une seule VM (les 4 techniciens partagent son processeur, partage SMB en boucle locale), un seul contrôleur de domaine '
           '(plusieurs contrôleurs avec réplication : non testé), parcours « Ajouter au domaine » seulement (le renommage n\'a pas de réservation AD), '
           '6 tours par case : les écarts entre réglages protégés ne sont pas significatifs, seul l\'écart avec et sans protection l\'est.</p></div>')
out.append('</main></body></html>')
(HERE / 'collisions-v2.html').write_text('\n'.join(out), 'utf-8')
print('collisions-v2.html', (HERE / 'collisions-v2.html').stat().st_size, 'octets')

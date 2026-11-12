// Aide : raccourcis, diagnostics lus du moteur (diagnostics.read), à-propos honnête. Aucun fait inventé : les
// diagnostics viennent du moteur ; ce qui n'est pas vérifié depuis ce poste est dit comme non vérifié.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, errorText, announce } from '../ui.js';
import { createTabs, pill } from '../kit/index.js';

const SHORTCUTS = [
  ['Ctrl B', 'Replier ou déplier le menu'],
  ['Ctrl K', 'Palette de commandes (écrans et actions de l’écran courant)'],
  ['Alt 1…9', 'Aller à un écran de la navigation'],
  ['F1', 'Ouvrir cette aide'],
  ['?', 'Ouvrir la fiche raccourcis de l’aide'],
  ['/', 'Rechercher un réglage (écran Paramètres)'],
  ['Échap', 'Fermer dialogue, palette ou menu'],
];

function layout() {
  return `<div class="page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon('info')}</span>
        <div class="titles"><h1 class="gradient-text">Aide</h1>
          <p class="subtitle">Raccourcis, diagnostics du moteur et état réel de cette version.</p></div></div>
    </header>
    <section class="card reveal spot" data-zone="tabs"></section>
  </div>`;
}

export function render(main, ctx) {
  main.innerHTML = layout();
  applyVars(main);
  const stops = [reveal(main)];
  let alive = true;
  const host = main.querySelector('[data-zone="tabs"]');
  const wanted = ['apercu', 'raccourcis', 'diagnostics', 'apropos'].includes(ctx.params?.tab) ? ctx.params.tab : 'apercu';

  const tabs = createTabs(host, {
    label: 'Aide',
    key: 'aide',
    selected: wanted,
    tabs: [
      { id: 'apercu', label: 'Aperçu', icon: 'info', render: (panel) => {
        panel.innerHTML = `<div class="kv-grid">
          <span class="k">Produit</span><span class="v">Pesto 2 — postes du domaine (jonction, renommage, déplacement)</span>
          <span class="k">Moteur</span><span class="v">Liste fermée d’opérations (docs/BRIDGE.md) ; le moteur valide tout, l’interface n’invente rien</span>
          <span class="k">Écritures</span><span class="v">Aperçu du nom libre → plan lié → confirmation du plan affiché → exécution unique → reçu</span>
          <span class="k">Garde-fous</span><span class="v">Jonction locale seule ; même site = OU inchangée ; déplacement après relecture de l’identité et confirmation ; aucun redémarrage ni retrait Entra implicite ; incertain jamais rejoué</span>
          <span class="k">Simulation</span><span class="v">Monde fictif en mémoire, clairement marqué : aucun contact AD, réseau ou disque</span>
        </div>`;
      } },
      { id: 'raccourcis', label: 'Raccourcis', icon: 'command', render: (panel) => {
        panel.innerHTML = `<ul class="feature-list">${SHORTCUTS.map(([k, d], n) =>
          `<li data-j="${Math.min(n, 18)}"><span class="mk msg" aria-hidden="true"></span><span><span class="t"><kbd>${esc(k)}</kbd> ${esc(d)}</span></span></li>`).join('')}</ul>`;
      } },
      { id: 'diagnostics', label: 'Diagnostics', icon: 'shield', render: (panel) => {
        panel.innerHTML = '<p class="muted" aria-busy="true">Lecture des diagnostics…</p>';
        ctx.call('diagnostics.read').then((d) => {
          if (!alive) return;
          const rows = (d.checks ?? []).map((c, n) => {
            const tone = c.state === 'ok' ? 'ok' : c.state === 'unknown' ? 'warn' : 'alert';
            return `<li data-j="${Math.min(n, 18)}"><span class="mk msg" aria-hidden="true"></span><span>
              <span class="t">${esc(c.label)} ${pill(tone, c.state === 'ok' ? 'OK' : c.state === 'unknown' ? 'inconnu' : c.state, { size: 'sm' })}</span>
              <span class="d">${esc(c.detail ?? '')}</span></span></li>`;
          }).join('');
          panel.innerHTML = `<p class="muted small">Mode lu du moteur : ${esc(d.mode ?? 'inconnu')}.</p>
            <ul class="feature-list cascade">${rows || '<li>Aucun diagnostic renvoyé.</li>'}</ul>`;
          applyVars(panel);
        }).catch((err) => {
          if (!alive) return;
          panel.innerHTML = `<p class="muted" role="alert">${icon('alert')} ${esc(errorText(err))}</p>`;
          announce(`Diagnostics indisponibles : ${errorText(err)}`, { assertive: true });
        });
      } },
      { id: 'apropos', label: 'À propos', icon: 'sparkles', render: (panel) => {
        const s = ctx.session();
        panel.innerHTML = `<div class="kv-grid">
          <span class="k">Version du moteur</span><span class="v mono">${esc(s?.version ?? 'inconnue')}</span>
          <span class="k">Mode</span><span class="v">${s?.mode === 'simulation' ? 'Simulation en mémoire (aucun effet réel)' : s?.configurationOnly ? 'Configuration locale — annuaire non connecté' : s ? 'Annuaire réel' : 'inconnu'}</span>
          <span class="k">Qualification Windows/AD</span><span class="v">Candidat V2 : consulter les preuves associées à ce pack. La disponibilité des actions ne vaut pas qualification AD.</span>
        </div>`;
      } },
    ],
  });

  ctx.setScreenCommands([
    { id: 'aide-diagnostics', kind: 'command', label: 'Ouvrir les diagnostics', icon: 'shield', group: 'Aide', effect: 'read', available: true, detailText: 'Lit diagnostics.read du moteur.', run: () => tabs.select('diagnostics') },
  ]);

  return () => { alive = false; ctx.setScreenCommands([]); stops.forEach((stop) => stop()); };
}

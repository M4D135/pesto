// Defensive router fallback, reached only when a page module fails to load or a route names no known screen.
// The nine mission screens each have their own module (web-check controls this): this page must never present a
// ported screen as "in progress", and never pretends a capability exists.
import { icon } from '../icons.js';
import { esc, applyVars, reveal, announce } from '../ui.js';

function layout(page) {
  const section = page.section ? `${page.section} · ` : '';
  return `<div class="page todo-page">
    <header class="page-header reveal">
      <div class="head-row"><span class="page-icon">${icon(page.icon)}</span>
        <div class="titles"><h1 class="gradient-text">${esc(page.label)}</h1>
          <p class="subtitle">${esc(section)}Pesto 2</p></div></div>
      <div class="actions">
        <button class="btn" type="button" data-act="palette">${icon('command')}Palette de commandes</button>
        <button class="btn primary" type="button" data-act="home">${icon('home')}Retour à l’accueil</button>
      </div>
    </header>
    <section class="card todo-hero reveal spot">
      <div class="empty">
        <div class="art">${icon(page.icon)}</div>
        <h2>Écran indisponible</h2>
        <p>Le module de cet écran n’a pas pu être chargé, ou cette adresse ne correspond à aucun écran déclaré.
          Vérifiez l’intégrité du pack portable puis relancez. Aucune action d’écriture n’est admise depuis cet écran
          : les écritures passent uniquement par les écrans raccordés au moteur (aperçu, plan, confirmation exacte,
          reçu, relecture) et restent soumises aux capacités et garde-fous du moteur.</p>
      </div>
    </section>
  </div>`;
}

export function render(main, ctx) {
  const { page } = ctx;
  main.innerHTML = layout(page);
  applyVars(main);
  const stops = [reveal(main)];
  main.querySelector('[data-act="home"]').addEventListener('click', () => ctx.navigate('accueil'));
  main.querySelector('[data-act="palette"]').addEventListener('click', () => ctx.openPalette());
  announce(`Écran ${page.label} : indisponible, aucune action admise depuis ce repli.`);
  return () => stops.forEach((stop) => stop());
}
